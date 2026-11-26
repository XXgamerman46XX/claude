import SwiftUI

struct Floater: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
    let big: Bool
    let xOffset: CGFloat
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let icon: String
}

/// Owns the game state, runs the game loop, saves, and turns events into UI effects.
final class GameModel: ObservableObject {
    @Published var core: GameCore
    @Published var floaters: [Floater] = []
    @Published var toast: Toast?
    @Published var offlineReport: OfflineReport?
    @Published var showPrestige = false
    @Published var showVictory = false
    @Published var tapPulse = 0

    private var timer: Timer?
    private var saveCountdown = 0.0
    private var autoTapCarry = 0.0
    private var achievementCountdown = 0.0
    private var autoPulseCount = 0
    private let saveKey = "deepcore.save.v1"
    private let haptics = Haptics()
    private let tickInterval = 0.1

    init() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let saved = try? JSONDecoder().decode(GameCore.self, from: data) {
            core = saved
        } else {
            core = GameCore()
        }
        startTimer()
    }

    // MARK: Player actions

    func tap() {
        let events = core.tap()
        tapPulse &+= 1
        haptics.tap()
        handle(events, fromTap: true)
    }

    func buy(_ kind: UpgradeKind, count: Int) {
        if core.buy(kind, count: count) > 0 { haptics.tap() }
    }

    func setAutoTap(enabled: Bool) {
        core.autoTapEnabled = enabled
        autoTapCarry = 0
        haptics.tap()
    }

    func setAutoTap(rate: Double) {
        core.autoTapRate = rate
    }

    /// Fires the auto clicker's taps for this tick. Fractional taps carry over,
    /// so 1, 2, 5, 10 and 20 taps/sec are all exact over time.
    private func runAutoClicker() {
        guard core.autoTapEnabled else { return }
        autoTapCarry += core.autoTapRate * tickInterval
        var events: [GameEvent] = []
        while autoTapCarry >= 1 {
            autoTapCarry -= 1
            events += core.tap(manual: false)
        }
        if !events.isEmpty {
            autoPulseCount &+= 1
            if autoPulseCount % 2 == 0 { tapPulse &+= 1 }
            handle(events, fromTap: false)
        }
    }

    private func announce(_ fresh: [Achievement]) {
        guard let first = fresh.first else { return }
        let bonus = Int((Balance.achievementBonusEach * 100).rounded()) * fresh.count
        if fresh.count == 1 {
            showToast("Achievement: \(first.title)! +\(bonus)% forever", icon: "trophy.fill")
        } else {
            showToast("\(fresh.count) achievements unlocked! +\(bonus)% forever", icon: "trophy.fill")
        }
        haptics.success()
    }

    func challengeBoss() {
        handle(core.challengeBoss(), fromTap: true)
    }

    func prestige() {
        let gain = core.pendingShards
        core.prestige()
        showPrestige = false
        showToast("Smelted \(gain) Core Shards. Dig again, stronger!", icon: "sparkles")
        haptics.success()
        save()
    }

    func resetEverything() {
        core = GameCore()
        floaters = []
        save()
    }

    // MARK: Loop

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func step() {
        let events = core.tick(dt: tickInterval)
        if !events.isEmpty { handle(events, fromTap: false) }
        runAutoClicker()
        achievementCountdown += tickInterval
        if achievementCountdown >= 1 {
            achievementCountdown = 0
            announce(core.checkAchievements())
        }
        saveCountdown += tickInterval
        if saveCountdown >= 15 {
            saveCountdown = 0
            save()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            applyOfflineProgress()
            startTimer()
        case .background:
            timer?.invalidate()
            save()
        default:
            save()
        }
    }

    private func applyOfflineProgress() {
        let away = Date().timeIntervalSince(core.lastSaved)
        if away > 60 {
            var copy = core
            if let report = copy.simulateOffline(seconds: away) {
                core = copy
                offlineReport = report
            }
        }
        core.lastSaved = Date()
    }

    func save() {
        core.lastSaved = Date()
        if let data = try? JSONEncoder().encode(core) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    // MARK: Events → effects

    private func handle(_ events: [GameEvent], fromTap: Bool) {
        for e in events {
            switch e {
            case let .hit(amount, crit):
                // Auto clicker hits only show a number now and then, so the screen stays readable.
                if fromTap || floaters.count < 3 {
                    addFloater(text: (crit ? "CRIT " : "") + Fmt.num(amount),
                               color: crit ? .yellow : .white.opacity(fromTap ? 1 : 0.7), big: crit)
                }
            case let .blockBroken(coins, ore):
                if fromTap || floaters.count < 4 {
                    addFloater(text: "+\(Fmt.num(coins))", color: Color(hex: ore.color), big: ore.rarity == 2)
                }
                if fromTap { haptics.breakBlock(rare: ore.rarity == 2) }
            case let .enteredBiome(b):
                showToast("Entered \(b.name)", icon: "map.fill")
            case let .bossStarted(b):
                showToast("BOSS: \(b.boss)! Break it in \(Int(core.bossTimeLimit))s", icon: "exclamationmark.triangle.fill")
                haptics.warning()
            case let .bossDefeated(b, relic):
                showToast(relic ? "\(b.boss) defeated! Relic earned: x1.45 forever"
                                : "\(b.boss) defeated!", icon: "crown.fill")
                haptics.success()
            case let .bossFailed(b):
                showToast("\(b.boss) was too tough. Upgrade and try again!", icon: "arrow.uturn.backward")
                haptics.error()
            case .coreReached:
                showVictory = true
                save()
            }
        }
    }

    private func addFloater(text: String, color: Color, big: Bool) {
        let f = Floater(text: text, color: color, big: big, xOffset: CGFloat.random(in: -70...70))
        floaters.append(f)
        if floaters.count > 14 { floaters.removeFirst(floaters.count - 14) }
        let id = f.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            self?.floaters.removeAll { $0.id == id }
        }
    }

    private func showToast(_ text: String, icon: String) {
        let t = Toast(text: text, icon: icon)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            if self?.toast?.id == t.id { self?.toast = nil }
        }
    }
}
