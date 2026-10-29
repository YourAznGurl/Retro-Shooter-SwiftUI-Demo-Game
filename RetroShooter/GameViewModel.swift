import SwiftUI

// Value types keep each entity's motion and collision state together.
struct Bullet: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity = CGVector(dx: 0, dy: -500)
    static let size = CGSize(width: 4, height: 14)
}

struct Enemy: Identifiable {
    enum Kind { case boss, escort, grunt }
    let id = UUID()
    let slot: Int
    var position: CGPoint
    var arrived = false
    var health: Int = 1
    var diveTime: CGFloat?
    var diveOrigin = CGPoint.zero
    var targetX: CGFloat = 0
    var returning = false
    var shotAt: CGFloat = 0
    var entranceShotFired = false
    var hasCapturedShip = false
    var kind: Kind { slot < 8 ? .boss : (slot < 24 ? .escort : .grunt) }
    static let size = CGSize(width: 24, height: 22)
}

@MainActor
final class GameViewModel: ObservableObject {
    enum Status { case attract, ready, playing, stageComplete, captured, gameOver, nameRegistration }
    @Published private(set) var status: Status = .attract
    @Published private(set) var score = 0
    @Published private(set) var highScore = UserDefaults.standard.integer(forKey: "highScore")
    @Published private(set) var highScoreName = UserDefaults.standard.string(forKey: "highScoreName") ?? "AAA"
    @Published private(set) var credits = 0
    @Published private(set) var reserveLives = 3
    @Published private(set) var playerX: CGFloat = 0
    @Published private(set) var bullets: [Bullet] = []
    @Published private(set) var enemyBullets: [Bullet] = []
    @Published private(set) var enemies: [Enemy] = []
    @Published private(set) var playfield: CGSize = .zero
    @Published private(set) var elapsed: CGFloat = 0
    @Published private(set) var stageTime: CGFloat = 0
    @Published private(set) var invulnerability: CGFloat = 0
    @Published private(set) var stage = 1
    @Published private(set) var dualFighter = false
    @Published private(set) var challengeHits = 0
    @Published private(set) var challengeBonus = 0
    @Published private(set) var beam: CGRect?
    @Published private(set) var capturedPosition: CGPoint?
    @Published var soundEnabled = true
    var onSound: ((String) -> Void)?
    static let playerSize = CGSize(width: 30, height: 28)
    var playerY: CGFloat { max(0, playfield.height - 32) }
    var isChallenge: Bool { stage >= 3 && (stage - 3) % 4 == 0 }
    var runActive: Bool { [.playing, .stageComplete, .captured].contains(status) }
    var entering: Bool { stageTime < entranceEnd }
    var difficulty: CGFloat { min(3.5, 1 + CGFloat(stage - 1) * 0.13) }
    var entranceEnd: CGFloat { 4 * groupDelay + 7 * 0.16 + entranceDuration }
    private var groupDelay: CGFloat { 2.4 / sqrt(difficulty) }
    private var entranceDuration: CGFloat { 3.4 / sqrt(difficulty) }
    private var lastTick: Date?
    private var accumulator: CGFloat = 0
    private var lastShot: Date?
    private var nextBonus = 20_000
    private var transitionTime: CGFloat = 0
    private var nextDive: CGFloat = 0
    private var nextEnemyShot: CGFloat = 0
    private var startingHighScore = 0
    private var beamExposure: CGFloat = 0
    private var exposureBoss: UUID?
    private var captureOrigin = CGPoint.zero
    private var captureBoss: UUID?

    func sound(_ event: String) { if soundEnabled { onSound?(event) } }
    func resize(to size: CGSize) {
        guard size.width > 0, size.height > 0, size != playfield else { return }
        let old = playfield
        playfield = size
        playerX = old.width == 0 ? size.width / 2 : playerX * size.width / old.width
        clampPlayer()
        bullets.removeAll(); enemyBullets.removeAll()
        resetClock()
    }
    func insertCoin() {
        credits = min(99, credits + 1)
        if [.attract, .gameOver].contains(status) { status = .ready }
    }
    func startGame() {
        guard credits > 0, !runActive, status != .nameRegistration, playfield != .zero else { return }
        credits -= 1
        score = 0; reserveLives = 3; nextBonus = 20_000; stage = 1
        dualFighter = false; startingHighScore = highScore
        playerX = playfield.width / 2
        beginStage()
        resetClock()
    }
    private func beginStage() {
        stageTime = 0; invulnerability = 3; transitionTime = 0
        challengeHits = 0; challengeBonus = 0
        bullets = []; enemyBullets = []; beam = nil; capturedPosition = nil
        lastShot = nil; captureBoss = nil; beamExposure = 0; exposureBoss = nil
        enemies = (0..<40).map {
            Enemy(slot: $0, position: CGPoint(x: -40, y: -40), health: $0 < 8 && !isChallenge ? 2 : 1)
        }
        nextEnemyShot = 1.2
        nextDive = entranceEnd + 0.8
        status = .playing
        sound("start")
    }
    func resetClock() { lastTick = nil; accumulator = 0 }
    func movePlayer(to x: CGFloat) {
        guard status == .playing else { return }
        playerX = x; clampPlayer()
    }
    private func clampPlayer() {
        let inset: CGFloat = dualFighter ? 38 : 23
        playerX = min(max(playerX, inset), max(inset, playfield.width - inset))
    }
    func stepPlayer(_ direction: CGFloat) { movePlayer(to: playerX + direction * 30) }
    func fire(at date: Date = .now) {
        let count = dualFighter ? 2 : 1
        guard status == .playing, bullets.count + count <= (dualFighter ? 4 : 2) else { return }
        if let lastShot, date.timeIntervalSince(lastShot) < 0.18 { return }
        lastShot = date
        for offset: CGFloat in (dualFighter ? [-16, 16] : [0]) {
            bullets.append(Bullet(position: CGPoint(x: playerX + offset, y: playerY - 22)))
        }
        sound("fire")
    }
    func formationPosition(slot: Int, time: CGFloat) -> CGPoint {
        let spacing = min(30, playfield.width / 10) * (1 + 0.12 * sin(time * 2))
        return CGPoint(x: playfield.width / 2 + (CGFloat(slot % 8) - 3.5) * spacing + sin(time * 0.9) * 8,
                       y: 42 + CGFloat(slot / 8) * min(30, playfield.height * 0.055))
    }
    private func delay(_ slot: Int) -> CGFloat { CGFloat(slot / 8) * groupDelay + CGFloat(slot % 8) * 0.16 }
    /// Cubic Bezier entrances approach from alternating edges in five groups.
    func entrancePosition(slot: Int, time: CGFloat) -> CGPoint {
        let t = min(1, max(0, (time - delay(slot)) / entranceDuration))
        let end = formationPosition(slot: slot, time: time)
        let left = slot / 8 % 2 == 0
        let a = CGPoint(x: left ? -35 : playfield.width + 35, y: -30)
        let b = CGPoint(x: left ? playfield.width * 0.9 : playfield.width * 0.1, y: playfield.height * 0.8)
        let c = CGPoint(x: left ? -playfield.width * 0.25 : playfield.width * 1.25, y: playfield.height * 0.45)
        let u = 1 - t
        return CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*end.x,
                       y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*end.y)
    }
    /// Accumulate real time, then simulate in fixed 1/60-second steps.
    func tick(at date: Date) {
        guard playfield != .zero else { return }
        guard let previous = lastTick else { lastTick = date; return }
        lastTick = date
        accumulator += CGFloat(min(max(date.timeIntervalSince(previous), 0), 0.1))
        while accumulator >= 1.0 / 60 {
            update(delta: 1.0 / 60)
            accumulator -= 1.0 / 60
        }
    }
    private func update(delta: CGFloat) {
        elapsed += delta
        if status == .stageComplete {
            transitionTime += delta
            if transitionTime >= 3.5 { stage += 1; beginStage() }
            return
        }
        if status == .captured {
            transitionTime += delta
            let target = enemies.first(where: { $0.id == captureBoss })?.position ?? CGPoint(x: playerX, y: 50)
            let t = min(1, transitionTime / 1.8)
            capturedPosition = CGPoint(x: captureOrigin.x + (target.x - captureOrigin.x) * t,
                                       y: captureOrigin.y + (target.y + 26 - captureOrigin.y) * t)
            if transitionTime >= 2 { capturedPosition = nil; respawn(); }
            return
        }
        guard status == .playing else { return }
        stageTime += delta
        invulnerability = max(0, invulnerability - delta)
        beam = nil
        captureBoss = nil
        updateEnemies(delta: delta)
        if !isChallenge, stageTime >= nextDive {
            launchDive()
            nextDive = stageTime + CGFloat.random(in: 1.8...3.2) / difficulty
        }
        moveProjectiles(delta: delta)
        resolvePlayerShots()
        if !isChallenge { resolvePlayerDamage(delta: delta) }
        if status == .playing && enemies.isEmpty { completeStage() }
    }
    private func updateEnemies(delta: CGFloat) {
        var escaped = Set<UUID>()
        for i in enemies.indices {
            let slot = enemies[i].slot
            let local = stageTime - delay(slot)
            if isChallenge {
                // Challenge enemies cross once and leave. No fire, ramming, or capture.
                let t = local / (entranceDuration + 1.3)
                if t > 1 { escaped.insert(enemies[i].id); continue }
                let p = max(0, t)
                let left = slot / 8 % 2 == 0
                enemies[i].position = CGPoint(x: (left ? p : 1-p) * (playfield.width + 70) - 35,
                    y: 50 + CGFloat(slot % 8) * 17 + sin(p * .pi * 2) * 38)
                continue
            }
            enemies[i].arrived = local >= entranceDuration
            if let start = enemies[i].diveTime {
                let age = stageTime - start
                let duration = 3.4 / sqrt(difficulty)
                let beamAttempt = enemies[i].kind == .boss && !dualFighter && !enemies.contains(where: { $0.hasCapturedShip })
                if beamAttempt && age >= 0.8 && age < 3.6 {
                    enemies[i].position = CGPoint(x: enemies[i].targetX, y: playfield.height * 0.42)
                    // Extend the visible beam before it can reach the fighter.
                    let top = enemies[i].position.y + 15
                    let extensionProgress = min(1, (age - 0.8) / 0.7)
                    beam = CGRect(x: enemies[i].position.x - 25, y: top,
                                  width: 50, height: max(0, playfield.height - 8 - top) * extensionProgress)
                    captureBoss = enemies[i].id
                } else {
                    let adjusted = age - (beamAttempt && age >= 3.6 ? 2.8 : 0)
                    if adjusted <= duration {
                        let p = max(0, adjusted / duration)
                        let origin = enemies[i].diveOrigin
                        enemies[i].position = CGPoint(x: origin.x + (enemies[i].targetX - origin.x) * p
                            + sin(p * .pi * 2) * 35,
                            y: origin.y + p * (playfield.height + 35 - origin.y))
                    } else {
                        enemies[i].returning = true
                        let p = min(1, (adjusted - duration) / 1.2)
                        let home = formationPosition(slot: slot, time: stageTime)
                        enemies[i].position = CGPoint(x: home.x, y: -30 + (home.y + 30) * p)
                        if p >= 1 { enemies[i].diveTime = nil; enemies[i].returning = false }
                    }
                }
            } else {
                enemies[i].position = entrancePosition(slot: slot, time: stageTime)
            }
            // Early stages get isolated shots, rather than eight ships firing together.
            let entranceShooters = min(3, 1 + max(0, stage - 2) / 3)
            let entranceShot = stage >= 2 && !enemies[i].arrived && local > 1
                && slot % 8 < entranceShooters && !enemies[i].entranceShotFired
            let divingShot = enemies[i].diveTime != nil && !enemies[i].returning
            let bulletLimit = min(10, 3 + max(0, stage - 2) / 2)
            if (entranceShot || divingShot) && beam == nil,
               stageTime >= enemies[i].shotAt, stageTime >= nextEnemyShot,
               enemyBullets.count < bulletLimit {
                shootEnemy(from: enemies[i].position)
                if entranceShot { enemies[i].entranceShotFired = true }
                enemies[i].shotAt = stageTime + CGFloat.random(in: 2.4...3.4) / sqrt(difficulty)
                // A shared cooldown prevents simultaneous volleys across the swarm.
                nextEnemyShot = stageTime + max(0.3, 1 - CGFloat(stage) * 0.05)
            }
        }
        enemies.removeAll { escaped.contains($0.id) }
    }
    private func launchDive() {
        let available = enemies.indices.filter { enemies[$0].arrived && enemies[$0].diveTime == nil }
        guard let leader = available.randomElement() else { return }
        var selected = [leader]
        if enemies[leader].kind == .boss {
            selected += available.filter { enemies[$0].kind == .escort }.prefix(min(2, stage))
        }
        for i in selected { beginDive(at: i) }
        sound("dive")
    }
    func beginDive(at index: Int) {
        guard enemies.indices.contains(index) else { return }
        enemies[index].diveOrigin = enemies[index].position
        enemies[index].diveTime = stageTime
        enemies[index].targetX = min(max(playerX + CGFloat.random(in: -24...24), 28), playfield.width - 28)
        enemies[index].shotAt = stageTime + 0.45
    }
    private func shootEnemy(from point: CGPoint) {
        let speed = 135 + CGFloat(stage) * 5
        // Enemy shots fall vertically from the firing position, so moving aside dodges them.
        enemyBullets.append(Bullet(position: point, velocity: CGVector(dx: 0, dy: speed)))
    }
    private func moveProjectiles(delta: CGFloat) {
        for i in bullets.indices {
            bullets[i].position.x += bullets[i].velocity.dx * delta
            bullets[i].position.y += bullets[i].velocity.dy * delta
        }
        for i in enemyBullets.indices {
            enemyBullets[i].position.x += enemyBullets[i].velocity.dx * delta
            enemyBullets[i].position.y += enemyBullets[i].velocity.dy * delta
        }
        bullets.removeAll { $0.position.y < -20 }
        enemyBullets.removeAll { $0.position.y > playfield.height + 20 || $0.position.x < -20 || $0.position.x > playfield.width + 20 }
    }
    private func resolvePlayerShots() {
        var used = Set<UUID>()
        for bullet in bullets {
            if let i = enemies.firstIndex(where: {
                frame(at: bullet.position, size: Bullet.size).intersects(frame(at: $0.position, size: Enemy.size))
            }) {
                used.insert(bullet.id)
                hitEnemy(at: i)
            }
        }
        bullets.removeAll { used.contains($0.id) }
    }
    // Internal so the standalone checks can verify multi-hit and rescue rules directly.
    func hitEnemy(at index: Int) {
        guard enemies.indices.contains(index) else { return }
        enemies[index].health -= 1
        if enemies[index].health > 0 { sound("hit"); return }
        let enemy = enemies.remove(at: index)
        if captureBoss == enemy.id { beam = nil; captureBoss = nil; beamExposure = 0 }
        if enemy.hasCapturedShip {
            // Destroying the carrier releases its fighter in every flight phase.
            // Protect the newly widened ship so the rescue cannot be lost on this tick.
            dualFighter = true
            invulnerability = max(invulnerability, 3)
            clampPlayer()
            sound("rescue")
        }
        if isChallenge { challengeHits += 1 }
        addScore(enemy.kind == .boss ? 400 : enemy.kind == .escort ? 160 : 100)
        sound("explosion")
    }
    private func resolvePlayerDamage(delta: CGFloat) {
        guard invulnerability == 0 else { beamExposure = 0; return }
        let size = CGSize(width: dualFighter ? 62 : 30, height: 28)
        let player = frame(at: CGPoint(x: playerX, y: playerY), size: size)
        let center = CGPoint(x: playerX, y: playerY)
        // A wing brushing the beam isn't enough: the center must stay inside
        // the drawn beam for a short interval. Moving out cancels the pull.
        if !dualFighter, let beam, beam.contains(center), let id = captureBoss {
            if exposureBoss != id { beamExposure = 0; exposureBoss = id }
            beamExposure += delta
            if beamExposure >= 0.25 {
                capturePlayer(by: id)
                if status == .captured { return }
            }
        } else {
            beamExposure = 0; exposureBoss = nil
        }
        if let shot = enemyBullets.firstIndex(where: { frame(at: $0.position, size: Bullet.size).intersects(player) }) {
            enemyBullets.remove(at: shot); loseShip()
        } else if enemies.contains(where: { frame(at: $0.position, size: Enemy.size).intersects(player) }) {
            loseShip()
        }
    }
    func capturePlayer(by bossID: UUID) {
        guard status == .playing, !dualFighter, invulnerability == 0,
              captureBoss == bossID, beamExposure >= 0.25,
              let beam, beam.contains(CGPoint(x: playerX, y: playerY)),
              let index = enemies.firstIndex(where: { $0.id == bossID && $0.kind == .boss && $0.diveTime != nil }) else { return }
        enemies[index].hasCapturedShip = true
        captureBoss = bossID
        captureOrigin = CGPoint(x: playerX, y: playerY)
        capturedPosition = captureOrigin
        transitionTime = 0; status = .captured
        sound("capture")
    }
    func loseShip() {
        sound("explosion")
        if dualFighter { dualFighter = false; invulnerability = 3; clampPlayer() }
        else { respawn() }
    }
    private func respawn() {
        beam = nil; beamExposure = 0; exposureBoss = nil
        if reserveLives > 0 {
            reserveLives -= 1; playerX = playfield.width / 2
            invulnerability = 3; bullets = []; enemyBullets = []; status = .playing
        } else {
            bullets = []; enemyBullets = []; beam = nil
            status = score > startingHighScore ? .nameRegistration : .gameOver
        }
    }
    func registerName(_ name: String) {
        guard status == .nameRegistration else { return }
        let clean = String(name.uppercased().filter { $0.isASCII && $0.isLetter }.prefix(3))
        highScoreName = clean.isEmpty ? "AAA" : clean
        UserDefaults.standard.set(highScoreName, forKey: "highScoreName")
        status = credits > 0 ? .ready : .gameOver
    }
    private func completeStage() {
        if isChallenge {
            challengeBonus = challengeHits == 40 ? 10_000 : challengeHits * 100
            addScore(challengeBonus)
        }
        status = .stageComplete; transitionTime = 0
        bullets = []; enemyBullets = []; beam = nil
        sound("start")
    }
    private func addScore(_ points: Int) {
        score += points
        if score > highScore { highScore = score; UserDefaults.standard.set(score, forKey: "highScore") }
        while score >= nextBonus {
            reserveLives += 1
            nextBonus = nextBonus == 20_000 ? 70_000 : nextBonus + 70_000
        }
    }
    private func frame(at point: CGPoint, size: CGSize) -> CGRect {
        CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }
}
