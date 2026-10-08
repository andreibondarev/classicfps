/* tslint:disable */
/* eslint-disable */

/**
 * Get interpolated player state at a given time
 * Uses binary search for O(log n) performance
 */
export function get_state_at_time(timeline_js: any, time: number): any;

/**
 * Parse a BSP file and return flattened geometry arrays for Three.js
 */
export function parse_bsp(data: Uint8Array): any;

/**
 * Textured BSP parse: per-texture geometry groups + RGBA pixels.
 * `wads` is a JS array of Uint8Array WAD3 file contents.
 */
export function parse_bsp_textured(data: Uint8Array, wads: Array<any>): any;

/**
 * Parse a demo file and return the timeline for playback
 */
export function parse_demo(data: Uint8Array): any;

/**
 * SoA parse entry point: returns a JS object with typed arrays for the
 * timeline (zero-copy transferable from a worker) and a JSON string for the
 * small metadata (events, roster, map name).
 */
export function parse_demo_soa(data: Uint8Array, progress: Function): any;

/**
 * Like `parse_demo`, but reports progress (0.0..=1.0) through the given JS
 * callback and returns the result as a JSON string (serde_wasm_bindgen's
 * JsValue conversion takes ~50s for a full timeline; serde_json + JSON.parse
 * on the JS side is orders of magnitude faster). Intended to be called from
 * a Web Worker so the UI can render while parsing.
 */
export function parse_demo_with_progress(data: Uint8Array, progress: Function): string;

/**
 * Parse a GoldSrc studio model (.mdl): static-pose geometry + textures.
 */
export function parse_mdl(data: Uint8Array): any;

/**
 * Parse a p_ weapon model bone-merged onto a player model's skeleton.
 */
export function parse_mdl_attached(player: Uint8Array, weapon: Uint8Array): any;

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly get_state_at_time: (a: any, b: number) => [number, number, number];
    readonly parse_bsp: (a: number, b: number) => [number, number, number];
    readonly parse_bsp_textured: (a: number, b: number, c: any) => [number, number, number];
    readonly parse_demo: (a: number, b: number) => [number, number, number];
    readonly parse_demo_soa: (a: number, b: number, c: any) => [number, number, number];
    readonly parse_demo_with_progress: (a: number, b: number, c: any) => [number, number, number, number];
    readonly parse_mdl: (a: number, b: number) => [number, number, number];
    readonly parse_mdl_attached: (a: number, b: number, c: number, d: number) => [number, number, number];
    readonly __wbindgen_malloc: (a: number, b: number) => number;
    readonly __wbindgen_realloc: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_exn_store: (a: number) => void;
    readonly __externref_table_alloc: () => number;
    readonly __wbindgen_externrefs: WebAssembly.Table;
    readonly __externref_table_dealloc: (a: number) => void;
    readonly __wbindgen_free: (a: number, b: number, c: number) => void;
    readonly __wbindgen_start: () => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
