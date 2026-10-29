import SwiftUI

@main
struct ArcadeChecks {
    @MainActor static func main() {
        let game = GameViewModel()
        game.soundEnabled = false
        game.resize(to: CGSize(width: 390, height: 600))
        var clock = Date(timeIntervalSince1970: 1000)
        func advance(_ seconds: Double) {
            for _ in 0..<Int(seconds * 60) {
                clock = clock.addingTimeInterval(1.0 / 60)
                game.tick(at: clock)
            }
        }
        func clearStage() {
            while !game.enemies.isEmpty { game.hitEnemy(at: 0) }
            advance(0.1)
            assert(game.status == .stageComplete)
        }
        assert(game.status == .attract)
        game.startGame()
        assert(game.status == .attract)
        game.insertCoin(); game.startGame(); game.tick(at: clock)
        assert(game.credits == 0 && game.enemies.count == 40 && game.reserveLives == 3)
        assert(game.enemies.filter { $0.kind == .boss }.count == 8)
        let bossID = game.enemies[0].id
        game.hitEnemy(at: 0)
        assert(game.enemies.count == 40 && game.enemies[0].health == 1 && game.score == 0)
        game.hitEnemy(at: 0)
        assert(!game.enemies.contains { $0.id == bossID } && game.score == 400)
        game.fire(at: clock); game.fire(at: clock.addingTimeInterval(0.2)); game.fire(at: clock.addingTimeInterval(0.4))
        assert(game.bullets.count == 2)
        advance(4)
        assert(game.enemyBullets.isEmpty) // No entrance shooting in stage 1.
        clearStage()
        let lives = game.reserveLives
        advance(3.6)
        assert(game.stage == 2 && game.status == .playing && game.reserveLives == lives)
        assert(game.difficulty > 1)
        advance(1.5)
        assert(!game.enemyBullets.isEmpty) // Stage 2 shoots on entrance.
        let shot = game.enemyBullets[0]
        assert(shot.velocity.dx == 0 && shot.velocity.dy > 0)
        game.movePlayer(to: 26)
        advance(0.1)
        guard let fallingShot = game.enemyBullets.first(where: { $0.id == shot.id }) else {
            fatalError("Expected the shot to remain on screen")
        }
        assert(fallingShot.position.x == shot.position.x && fallingShot.position.y > shot.position.y)
        var entranceShots = Set(game.enemyBullets.map(\.id))
        while game.entering {
            advance(1.0 / 60)
            entranceShots.formUnion(game.enemyBullets.map(\.id))
            assert(game.enemyBullets.count <= 3)
        }
        assert(entranceShots.count <= 5) // At most one shot per entrance group in stage 2.
        clearStage(); advance(3.6)
        assert(game.stage == 3 && game.isChallenge)
        let challengeLives = game.reserveLives
        for _ in 0..<1200 {
            advance(1.0 / 60)
            if game.status == .stageComplete { break }
        }
        assert(game.status == .stageComplete && game.challengeHits == 0 && game.challengeBonus == 0)
        assert(game.reserveLives == challengeLives && game.enemyBullets.isEmpty)
        advance(3.6)
        assert(game.stage == 4 && !game.isChallenge)
        clearStage(); advance(3.6)
        clearStage(); advance(3.6)
        clearStage(); advance(3.6)
        assert(game.stage == 7 && game.isChallenge)
        clearStage()
        assert(game.challengeHits == 40 && game.challengeBonus == 10_000)
        assert(game.reserveLives > 3) // Includes the 20,000-point extra ship.
        game.insertCoin()
        assert(game.status == .stageComplete && game.credits == 1)
        for rescuePhase in 0..<3 {
        let rescue = GameViewModel()
        rescue.soundEnabled = false
        rescue.resize(to: CGSize(width: 390, height: 600))
        rescue.insertCoin(); rescue.startGame()
        rescue.tick(at: clock)
        func advanceRescue(_ frames: Int) {
            for _ in 0..<frames {
                clock = clock.addingTimeInterval(1.0 / 60)
                rescue.tick(at: clock)
            }
        }
        advanceRescue(190) // Let respawn protection expire before testing capture.
        let carrier = rescue.enemies[0].id
        rescue.beginDive(at: 0)
        rescue.capturePlayer(by: carrier)
        assert(rescue.status == .playing) // No active beam: capture must be rejected.
        rescue.movePlayer(to: 26)
        advanceRescue(95)
        guard let beam = rescue.beam else { fatalError("Expected a visible tractor beam") }
        assert(rescue.status == .playing && !beam.contains(CGPoint(x: rescue.playerX, y: rescue.playerY)))
        rescue.movePlayer(to: beam.maxX + 10) // Wing overlaps, center stays outside.
        advanceRescue(18)
        assert(rescue.status == .playing)
        rescue.movePlayer(to: beam.midX)
        advanceRescue(6)
        assert(rescue.status == .playing) // Brief contact cannot instantly capture.
        rescue.movePlayer(to: 26)
        advanceRescue(6)
        rescue.movePlayer(to: beam.midX)
        advanceRescue(18)
        assert(rescue.status == .captured && rescue.capturedPosition != nil && rescue.beam != nil)
        advanceRescue(125)
        assert(rescue.status == .playing && rescue.reserveLives == 2)
        if rescuePhase > 0 {
            rescue.movePlayer(to: 26)
            for _ in 0..<300 {
                advanceRescue(1)
                if let boss = rescue.enemies.first(where: { $0.id == carrier }),
                   rescuePhase == 1 ? boss.returning : boss.diveTime == nil { break }
            }
        }
        let carrierIndex = rescue.enemies.firstIndex(where: { $0.id == carrier })!
        if rescuePhase == 0 { assert(rescue.enemies[carrierIndex].diveTime != nil) }
        if rescuePhase == 1 { assert(rescue.enemies[carrierIndex].returning) }
        if rescuePhase == 2 { assert(rescue.enemies[carrierIndex].diveTime == nil) }
        rescue.hitEnemy(at: carrierIndex)
        assert(!rescue.dualFighter) // The first hit only damages the boss.
        rescue.hitEnemy(at: carrierIndex)
        assert(rescue.dualFighter && rescue.invulnerability >= 3)
        assert(rescue.reserveLives == 2) // Rescue doesn't spend another life.
        rescue.fire(at: clock); rescue.fire(at: clock.addingTimeInterval(0.2)); rescue.fire(at: clock.addingTimeInterval(0.4))
        assert(rescue.bullets.count == 4)
        rescue.loseShip()
        assert(!rescue.dualFighter && rescue.reserveLives == 2)
        rescue.loseShip(); rescue.loseShip(); rescue.loseShip()
        assert(rescue.status == .gameOver || rescue.status == .nameRegistration)
        }
        print("PASS: credit gates, 40 enemies, two-hit bosses, missile cap, entrance fire, stage progression, stage 3/7 challenges, perfect bonus, extra life, credits during transitions, capture, replacement life, dive/return/formation rescue, dual missile cap, dual damage, game over")
    }
}
