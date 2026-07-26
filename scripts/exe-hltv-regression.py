#!/usr/bin/env python3
"""Exercise the four historical EXE HLTV demos through rendered reconstructed POV."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import time

from playwright.sync_api import sync_playwright


ROOT = Path(__file__).resolve().parents[1]
PORT = 5246
CAPTURE_ROOT = ROOT / "artifacts" / "exe-hltv"
CASES = [
    ("exe-vs-lamers", ROOT / "demos" / "exe_vs_lamers-1.dem", "de_dust2"),
    ("exe-vs-mc", ROOT / "demos" / "exe_vs_mc-1.dem", "de_aztec"),
    ("exe-vs-sisterhood", ROOT / "demos" / "exe_vs_sisterhood-1.dem", "de_nuke"),
    ("fs-vs-exe", ROOT / "demos" / "fs_vs_exe-1.dem", "de_prodigy"),
]


def audit_case(page, demo: Path, expected_map: str) -> dict[str, object]:
    with page.expect_file_chooser() as chooser:
        page.locator(".drop-zone").click()
    chooser.value.set_files(str(demo))
    page.wait_for_function(
        """() => {
          const p = window.demoPlayer;
          return p?.verificationReport?.status && p?.mapMesh && p?.assetPreflight;
        }""",
        timeout=120_000,
    )

    selection = page.evaluate(
        """() => {
          const p = window.demoPlayer;
          const candidates = [.2, .35, .5, .65, .8].map(fraction => {
            p.setFollowTarget(null, false);
            p.seekToTime(p.duration * fraction);
            return {
              time: p.currentTime,
              living: p.livingFollowTargets(),
              meshes: p.playerMeshes.size,
            };
          }).sort((left, right) =>
            right.living.length - left.living.length || right.meshes - left.meshes);
          const selected = candidates[0];
          p.seekToTime(selected.time);
          p.setFollowTarget(selected.living[0] ?? p.timeline.slot_names[0] ?? null, false);
          p.seekToTime(selected.time + .05);
          return { time: p.currentTime, target: p.followTarget };
        }"""
    )
    page.wait_for_timeout(1_500)

    result = page.evaluate(
        """({expectedMap, selection}) => {
          const p = window.demoPlayer;
          p.updatePlayback();
          p.renderer.render(p.scene, p.camera);
          const world = p.mapMesh?.getObjectByName('worldspawn');
          world?.geometry?.computeBoundingBox();
          const worldBounds = world?.geometry?.boundingBox ?? null;
          const materialList = world
            ? (Array.isArray(world.material) ? world.material : [world.material])
            : [];
          const materials = [...new Set(materialList)];
          const texturedMaterials = materials.filter(material => !!material.map).length;
          let visibleSkins = 0;
          let visibleWeapons = 0;
          let visiblePlayerMeshes = 0;
          const visiblePlayers = [];
          let visibleFallbackBodies = 0;
          let finiteScene = true;
          p.scene.traverse(object => {
            finiteScene &&= [object.position.x, object.position.y, object.position.z]
              .every(Number.isFinite);
            if (object.name === 'body' && object.visible) visibleFallbackBodies++;
          });
          for (const [name, mesh] of p.playerMeshes) {
            if (!mesh.visible) continue;
            visiblePlayerMeshes++;
            const hasSkin = !!mesh.getObjectByName('skin');
            const hasWeapon = !!mesh.getObjectByName('weapon');
            if (hasSkin) visibleSkins++;
            if (hasWeapon) visibleWeapons++;
            visiblePlayers.push({
              name,
              model: p.modelAt(name, p.currentTime),
              team: p.teamAt(name, p.currentTime),
              hasSkin,
              hasWeapon,
            });
          }

          const thumb = document.createElement('canvas');
          thumb.width = 64;
          thumb.height = 36;
          const context = thumb.getContext('2d', {willReadFrequently: true});
          context.drawImage(p.renderer.domElement, 0, 0, thumb.width, thumb.height);
          const pixels = context.getImageData(0, 0, thumb.width, thumb.height).data;
          const luma = [];
          for (let index = 0; index < pixels.length; index += 4) {
            luma.push((pixels[index] * 3 + pixels[index + 1] * 6 + pixels[index + 2]) / 10);
          }
          const mean = luma.reduce((sum, value) => sum + value, 0) / luma.length;
          const variance = luma.reduce((sum, value) => sum + (value - mean) ** 2, 0) / luma.length;
          const restoreTime = p.currentTime;
          const restoreTarget = p.followTarget;
          const rosterDeaths = p.computeDeaths(p.currentTime);
          p.renderPlayerList(rosterDeaths);
          const rosterRows = () => [...document.querySelectorAll(
            '#spectator-roster .spectator-player'
          )].map(row => ({
            name: row.dataset.player ?? '',
            dead: row.classList.contains('dead'),
            health: row.querySelector('.spectator-player-health')?.textContent?.trim() ?? '',
          }));
          const reconstructedRoster = rosterRows();
          const livingName = reconstructedRoster.find(row => !row.dead)?.name ?? '';
          let healthContract = {
            missing: '',
            zeroWhileLiving: '',
            positive: '',
            authoritativeDeath: '',
          };
          if (livingName) {
            const healthFor = () => rosterRows().find(row => row.name === livingName)?.health ?? '';
            const state = {name: livingName, health: -1, weapon: 0};
            p.renderPlayerList(rosterDeaths, [state]);
            healthContract.missing = healthFor();
            p.renderPlayerList(rosterDeaths, [{...state, health: 0}]);
            healthContract.zeroWhileLiving = healthFor();
            p.renderPlayerList(rosterDeaths, [{...state, health: 37}]);
            healthContract.positive = healthFor();
            const deathFixture = new Map(rosterDeaths);
            deathFixture.set(livingName, p.currentTime);
            p.renderPlayerList(deathFixture, [{...state, health: 0}]);
            healthContract.authoritativeDeath = healthFor();
            p.renderPlayerList(rosterDeaths);
          }
          if (!document.getElementById('stats-panel')) p.toggleStats();
          const roundResetFailures = [];
          const roundStarts = p.timeline.events.filter(event =>
            event.event_type === 'RoundStart' && event.time > 1);
          for (const event of roundStarts) {
            p.setFollowTarget(null, false);
            p.seekToTime(event.time + .05);
            const deaths = p.computeDeaths(p.currentTime);
            p.renderPlayerList(deaths);
            p.renderStatsPanel();
            const rosterDead = [...document.querySelectorAll('#players .player-entry.dead')]
              .map(element => element.dataset.name ?? element.textContent?.trim() ?? '');
            const scoreboardDead = [...document.querySelectorAll('#stats-panel tr.score-dead')]
              .map(element => element.querySelector('td')?.textContent?.trim() ?? '');
            if (deaths.size || rosterDead.length || scoreboardDead.length) {
              roundResetFailures.push({
                time: event.time,
                eventDeaths: [...deaths.keys()].sort(),
                rosterDead,
                scoreboardDead,
              });
            }
          }
          p.seekToTime(restoreTime);
          p.setFollowTarget(restoreTarget, false);

          return {
            expectedMap,
            map: p.mapName,
            duration: p.duration,
            verification: p.verificationReport?.status,
            checksum: p.verificationReport?.checksum,
            povSamples: p.timeline.povTimes.length,
            timelinePlayers: p.timeline.slot_names.length,
            shots: p.timeline.shotTimes.length,
            sounds: p.timeline.network_sounds.length,
            objects: p.timeline.objTimes.length,
            target: p.followTarget,
            selectedTime: selection.time,
            hudSource: document.getElementById('hud-source')?.textContent ?? '',
            mapVertices: world?.geometry?.getAttribute('position')?.count ?? 0,
            texturedMaterials,
            mapMaterials: materials.length,
            visiblePlayerMeshes,
            visibleSkins,
            visibleWeapons,
            visiblePlayers,
            visibleFallbackBodies,
            viewModelVisible: !!p.viewModel?.visible && p.viewModel.children.length > 0,
            camera: p.camera.position.toArray(),
            cameraInWorldBounds: !!worldBounds?.containsPoint(p.camera.position),
            worldBounds: worldBounds
              ? {
                  min: worldBounds.min.toArray(),
                  max: worldBounds.max.toArray(),
                }
              : null,
            finiteScene,
            lumaVariance: variance,
            roundStartsChecked: roundStarts.length,
            roundResetFailures,
            reconstructedRoster,
            healthContract,
            missingAssets: [...p.missingAssets].sort(),
            assetPreflight: p.assetPreflight,
          };
        }""",
        {"expectedMap": expected_map, "selection": selection},
    )
    return result


def valid_result(result: dict[str, object], errors: list[str]) -> bool:
    preflight = result.get("assetPreflight") or {}
    camera = result.get("camera") or []
    materials = int(result.get("mapMaterials") or 0)
    textured = int(result.get("texturedMaterials") or 0)
    return (
        not errors
        and result.get("map") == result.get("expectedMap")
        and result.get("verification") == "pass"
        and result.get("povSamples") == 0
        and int(result.get("timelinePlayers") or 0) >= 8
        and int(result.get("shots") or 0) > 500
        and int(result.get("sounds") or 0) > 1_000
        and int(result.get("objects") or 0) > 1_000
        and bool(result.get("target"))
        and "RECONSTRUCTED" in str(result.get("hudSource") or "").upper()
        and int(result.get("mapVertices") or 0) > 1_000
        and materials > 0
        and textured / materials >= .9
        and int(result.get("visiblePlayerMeshes") or 0) >= 2
        and result.get("visibleSkins") == result.get("visiblePlayerMeshes")
        and result.get("visibleWeapons") == result.get("visiblePlayerMeshes")
        and result.get("visibleFallbackBodies") == 0
        and bool(result.get("viewModelVisible"))
        and len(camera) == 3
        and all(isinstance(value, (int, float)) for value in camera)
        and bool(result.get("cameraInWorldBounds"))
        and bool(result.get("finiteScene"))
        and float(result.get("lumaVariance") or 0) > 25
        and int(result.get("roundStartsChecked") or 0) > 0
        and not result.get("roundResetFailures")
        and not any(
            not row.get("dead") and row.get("health") == "0 HP"
            for row in result.get("reconstructedRoster") or []
        )
        and any(
            not row.get("dead") and row.get("health") == "ALIVE"
            for row in result.get("reconstructedRoster") or []
        )
        and result.get("healthContract") == {
            "missing": "ALIVE",
            "zeroWhileLiving": "ALIVE",
            "positive": "37 HP",
            "authoritativeDeath": "DEAD",
        }
        and not result.get("missingAssets")
        and preflight.get("missing") == 0
    )


def main() -> int:
    CAPTURE_ROOT.mkdir(parents=True, exist_ok=True)
    server = subprocess.Popen(
        ["npm", "run", "dev", "--", "--host", "127.0.0.1", "--port", str(PORT)],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    results = []
    try:
        time.sleep(1)
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            page = browser.new_page(viewport={"width": 1440, "height": 900})
            page.goto(f"http://127.0.0.1:{PORT}", wait_until="networkidle")
            for name, demo, expected_map in CASES:
                errors: list[str] = []
                page.on("pageerror", lambda error, bucket=errors: bucket.append(str(error)))
                result = audit_case(page, demo, expected_map)
                page.locator("#canvas-container").screenshot(
                    path=CAPTURE_ROOT / f"{name}.png",
                )
                results.append({
                    "case": name,
                    "ok": valid_result(result, errors),
                    "result": result,
                    "errors": errors,
                })
                page.reload(wait_until="networkidle")
            browser.close()
    finally:
        server.terminate()
        server.wait(timeout=10)

    print(json.dumps(results, indent=2))
    passed = sum(bool(result["ok"]) for result in results)
    print(f"\nEXE HLTV regression: {passed}/{len(results)} passed")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
