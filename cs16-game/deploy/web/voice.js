// Protocol 47 browser voice: push-to-talk capture, Opus encode/decode via
// WebCodecs, and per-speaker playback. The game (Godot, through
// JavaScriptBridge) moves frames over its own WebSocket; the host decides who
// hears whom. Frames cross the bridge as base64 strings.
(() => {
  "use strict";
  const SAMPLE_RATE = 48000;
  const FRAME_SAMPLES = 960; // 20 ms
  const BITRATE = 24000;
  const JITTER_SECONDS = 0.08;
  const MAX_LAG_SECONDS = 0.35;
  const TALKING_HOLD_MS = 300;

  const WORKLET = `
    class P47Capture extends AudioWorkletProcessor {
      process(inputs) {
        const channel = inputs[0] && inputs[0][0];
        if (channel) this.port.postMessage(channel.slice(0));
        return true;
      }
    }
    registerProcessor("p47-capture", P47Capture);
  `;

  const state = {
    context: null,
    output: null,
    stream: null,
    encoder: null,
    pending: new Float32Array(0),
    timestamp: 0,
    transmitting: false,
    wantTransmit: false,
    opening: null,
    onFrame: null,
    micLevel: 0,
    speakers: new Map(),
    receiveVolume: 1,
    transmitGain: null,
    transmitGainValue: 1,
    error: "",
    stats: { framesSent: 0, framesReceived: 0, framesDecoded: 0, lastDecodedPeak: 0, maxCapturedPeak: 0, maxDecodedPeak: 0 },
  };

  const supported = () =>
    typeof AudioEncoder !== "undefined" && typeof AudioDecoder !== "undefined" &&
    !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia) && typeof AudioWorkletNode !== "undefined";

  function context() {
    if (!state.context) {
      state.context = new AudioContext({ sampleRate: SAMPLE_RATE, latencyHint: "interactive" });
      state.output = state.context.createGain();
      state.output.gain.value = state.receiveVolume;
      // Opus overshoots slightly on hard onsets and several teammates may talk
      // at once: limit the mix instead of clipping.
      const limiter = state.context.createDynamicsCompressor();
      limiter.threshold.value = -6;
      limiter.knee.value = 6;
      limiter.ratio.value = 12;
      limiter.attack.value = 0.003;
      limiter.release.value = 0.15;
      state.output.connect(limiter).connect(state.context.destination);
    }
    if (state.context.state === "suspended") state.context.resume().catch(() => {});
    return state.context;
  }

  function toBase64(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
  }

  function fromBase64(text) {
    const binary = atob(text);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }

  // Concurrent presses share one open; a failure (e.g. permission denied)
  // lets the next press try again.
  function openMicrophone() {
    if (!state.opening) {
      state.opening = openMicrophoneOnce().catch((error) => { state.opening = null; throw error; });
    }
    return state.opening;
  }

  async function openMicrophoneOnce() {
    const ctx = context();
    // ?voiceraw turns off the browser's speech processing (debugging a mic).
    const processing = !new URLSearchParams(location.search).has("voiceraw");
    state.stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1, echoCancellation: processing, noiseSuppression: processing, autoGainControl: processing },
    });
    const url = URL.createObjectURL(new Blob([WORKLET], { type: "application/javascript" }));
    await ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);
    const source = ctx.createMediaStreamSource(state.stream);
    state.transmitGain = ctx.createGain();
    state.transmitGain.gain.value = state.transmitGainValue;
    const capture = new AudioWorkletNode(ctx, "p47-capture");
    source.connect(state.transmitGain).connect(capture);
    capture.port.onmessage = (event) => captureBlock(event.data);
    state.encoder = new AudioEncoder({
      output: (chunk) => {
        if (!state.onFrame) return;
        const bytes = new Uint8Array(chunk.byteLength);
        chunk.copyTo(bytes);
        state.stats.framesSent++;
        state.onFrame(toBase64(bytes));
      },
      error: (error) => { state.error = String(error); },
    });
    state.encoder.configure({ codec: "opus", sampleRate: SAMPLE_RATE, numberOfChannels: 1, bitrate: BITRATE });
  }

  function captureBlock(block) {
    let peak = 0;
    for (let i = 0; i < block.length; i++) peak = Math.max(peak, Math.abs(block[i]));
    state.micLevel = Math.max(peak, state.micLevel * 0.9);
    if (state.transmitting) state.stats.maxCapturedPeak = Math.max(state.stats.maxCapturedPeak, peak);
    if (!state.transmitting || !state.encoder) {
      state.pending = new Float32Array(0);
      return;
    }
    const merged = new Float32Array(state.pending.length + block.length);
    merged.set(state.pending);
    merged.set(block, state.pending.length);
    let offset = 0;
    while (merged.length - offset >= FRAME_SAMPLES) {
      const frame = merged.slice(offset, offset + FRAME_SAMPLES);
      offset += FRAME_SAMPLES;
      const data = new AudioData({
        format: "f32-planar", sampleRate: SAMPLE_RATE, numberOfFrames: FRAME_SAMPLES,
        numberOfChannels: 1, timestamp: state.timestamp, data: frame,
      });
      state.timestamp += 20000;
      state.encoder.encode(data);
      data.close();
    }
    state.pending = merged.slice(offset);
  }

  function speaker(id) {
    let entry = state.speakers.get(id);
    if (entry) return entry;
    const ctx = context();
    entry = { next: 0, lastMs: 0, muted: false, decoder: null };
    entry.decoder = new AudioDecoder({
      output: (audio) => {
        const samples = new Float32Array(audio.numberOfFrames);
        audio.copyTo(samples, { planeIndex: 0, format: "f32-planar" });
        const rate = audio.sampleRate;
        audio.close();
        state.stats.framesDecoded++;
        let peak = 0;
        for (let i = 0; i < samples.length; i++) peak = Math.max(peak, Math.abs(samples[i]));
        state.stats.lastDecodedPeak = peak;
        state.stats.maxDecodedPeak = Math.max(state.stats.maxDecodedPeak, peak);
        if (entry.muted) return;
        const buffer = ctx.createBuffer(1, samples.length, rate);
        buffer.copyToChannel(samples, 0);
        const node = ctx.createBufferSource();
        node.buffer = buffer;
        node.connect(state.output);
        const now = ctx.currentTime;
        if (entry.next < now || entry.next - now > MAX_LAG_SECONDS) entry.next = now + JITTER_SECONDS;
        node.start(entry.next);
        entry.next += buffer.duration;
      },
      error: (error) => { state.error = String(error); },
    });
    entry.decoder.configure({ codec: "opus", sampleRate: SAMPLE_RATE, numberOfChannels: 1 });
    state.speakers.set(id, entry);
    return entry;
  }

  window.P47Voice = {
    supported,
    // callback(base64Frame) receives each encoded 20 ms frame while transmitting.
    setFrameCallback(callback) { state.onFrame = callback; },
    async setTransmitting(on) {
      if (!supported()) return false;
      // Follow the latest key state: a release while the microphone is still
      // opening (first press, permission prompt) must not leave it sending.
      state.wantTransmit = !!on;
      if (!on) { state.transmitting = false; return true; }
      try { await openMicrophone(); } catch (error) { state.error = String(error); return false; }
      state.transmitting = state.wantTransmit;
      return true;
    },
    // Opens the microphone without transmitting (Options > Voice > Test).
    async openMicrophone() {
      try { await openMicrophone(); return true; } catch (error) { state.error = String(error); return false; }
    },
    play(speakerId, sequence, base64Frame) {
      if (!supported()) return;
      const entry = speaker(speakerId);
      entry.lastMs = performance.now();
      state.stats.framesReceived++;
      try {
        entry.decoder.decode(new EncodedAudioChunk({ type: "key", timestamp: sequence * 20000, data: fromBase64(base64Frame) }));
      } catch (error) { state.error = String(error); }
    },
    talking() {
      const now = performance.now();
      return [...state.speakers.entries()].filter(([, s]) => now - s.lastMs < TALKING_HOLD_MS).map(([id]) => id).join(",");
    },
    setMuted(speakerId, muted) { speaker(speakerId).muted = !!muted; },
    setReceiveVolume(volume) {
      state.receiveVolume = Math.max(0, Math.min(2, volume));
      if (state.output) state.output.gain.value = state.receiveVolume;
    },
    setTransmitGain(gain) {
      state.transmitGainValue = Math.max(0, Math.min(4, gain));
      if (state.transmitGain) state.transmitGain.gain.value = state.transmitGainValue;
    },
    micLevel() { return state.micLevel; },
    isTransmitting() { return state.transmitting; },
    stats() { return JSON.stringify({ ...state.stats, error: state.error, speakers: state.speakers.size }); },
  };
})();
