#!/usr/bin/env python3
"""Pacing simulator for Deepcore Miner.

Mirrors the formulas in DeepcoreMiner/DeepcoreMiner/Model/Balance.swift and plays a
simple "greedy" player: taps 5x/sec for ACTIVE_MIN minutes per day, idles at 75%
bot speed for 16 hours, always buys the cheapest upgrade, and prestiges when it has
made no progress for 3 hours and would gain at least 5% more shards.

Usage:  python3 tools/balance_sim.py [key=value ...]
e.g.    python3 tools/balance_sim.py g0=1.17 relic=1.4

Prints each prestige and the day the Core (depth 300 boss) is beaten.
Last tuned result: Core reached on ~day 62 with ~29 prestiges.
If you change a number here, change it in Balance.swift too.
"""
import functools
import sys

P = dict(
    g0=1.165, gStep=0.003, hpBase=10, bossMult=30, blocks=8,
    valBase=3, valGrowth=1.135,
    drillCost=15, drillCG=1.10, botCost=50, botCG=1.11,
    refCost=200, refCG=1.22, refMult=1.12,
    shardPow=1.5, shardMult=0.05, relic=1.45,
    activeMin=40, tps=5, stallHours=3, days=150, idleEff=0.75,
)
for arg in sys.argv[1:]:
    k, v = arg.split("=")
    P[k] = float(v)

AVG_RARITY = 0.76 * 1 + 0.20 * 4 + 0.04 * 20   # expected ore value multiplier
CRIT_FACTOR = 1 + 0.05 * (3 - 1)                # base crit chance x crit multiplier


def drill(n): return (1 + n) * 2 ** (n // 25)
def bots(n): return n * 0.8 * 2 ** (n // 25)


@functools.lru_cache(None)
def hp_raw(depth):
    if depth <= 1:
        return P["hpBase"]
    return hp_raw(depth - 1) * (P["g0"] + P["gStep"] * ((depth - 1) // 25))


def hp(depth): return hp_raw(depth) * (P["bossMult"] if depth % 25 == 0 else 1)
def val(depth): return P["valBase"] * P["valGrowth"] ** (depth - 1) * AVG_RARITY
def shards_for(d): return int((d / 10) ** P["shardPow"]) if d >= 50 else 0


def run():
    shards = prestiges = 0
    best_ever = 1
    t = 0
    while True:
        dr = bo = rf = 0
        coins = 0.0
        depth, blk = 1, 0
        hp_left = hp(1)
        max_d, last_prog, run_t = 1, 0, 0
        gm = (1 + P["shardMult"] * shards) * P["relic"] ** ((best_ever - 1) // 25)
        while True:
            sec = t % 86400
            active = sec < P["activeMin"] * 60
            eff = 1.0 if active else (P["idleEff"] if sec < P["activeMin"] * 60 + 16 * 3600 else 0.0)
            dps = bots(bo) * gm + (drill(dr) * gm * P["tps"] * CRIT_FACTOR if active else 0)
            ref = P["refMult"] ** rf
            if depth % 25 == 0 and dps * 30 < hp(depth):
                # can't beat this boss yet: farm the layer above it
                coins += eff * dps / hp(depth - 1) * val(depth - 1) * gm * ref
            else:
                dmg = dps * eff
                while dmg > 0:
                    if dmg >= hp_left:
                        dmg -= hp_left
                        coins += val(depth) * gm * ref
                        blk += 1
                        if depth % 25 == 0 or blk >= P["blocks"]:
                            if depth == 300:
                                return t / 86400, prestiges
                            depth += 1
                            blk = 0
                            max_d = max(max_d, depth)
                            best_ever = max(best_ever, depth)
                            last_prog = run_t
                        hp_left = hp(depth)
                    else:
                        hp_left -= dmg
                        dmg = 0
            while True:
                opts = [(P["drillCost"] * P["drillCG"] ** dr, "d"),
                        (P["botCost"] * P["botCG"] ** bo, "b"),
                        (P["refCost"] * P["refCG"] ** rf, "r")]
                cost, kind = min(opts)
                if cost > coins:
                    break
                coins -= cost
                if kind == "d": dr += 1
                elif kind == "b": bo += 1
                else: rf += 1
            t += 1
            run_t += 1
            if t / 86400 >= P["days"]:
                return None, prestiges
            gain = shards_for(max_d)
            if run_t - last_prog > P["stallHours"] * 3600 and gain >= shards * 0.05 + 1:
                shards += gain
                prestiges += 1
                print(f"day {t / 86400:5.1f}  prestige #{prestiges:<3} reached depth {max_d:<4} shards {shards}")
                break


if __name__ == "__main__":
    day, n = run()
    if day is None:
        print(f"Did NOT reach the Core within {P['days']:.0f} days ({n} prestiges).")
    else:
        print(f"Core reached on day {day:.1f} after {n} prestiges.")
