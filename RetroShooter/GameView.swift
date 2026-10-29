import SwiftUI

struct GameView: View {
    @StateObject private var game = GameViewModel()
    @State private var initials = "AAA"
    @State private var audio = ArcadeAudio()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack { Text("1UP").foregroundStyle(.red); Text(String(format: "%06d", game.score)) }
                Spacer()
                VStack { Text("HIGH SCORE").foregroundStyle(.red); Text(String(format: "%06d", game.highScore)) }
            }
            .font(.system(.headline, design: .monospaced, weight: .bold))
            .padding()

            GeometryReader { geometry in
                // TimelineView redraws at animation cadence. onChange forwards each
                // new timestamp to the model without mutating state inside Canvas.
                TimelineView(.animation(paused: scenePhase != .active)) { timeline in
                    Canvas { context, size in
                        drawStars(context: &context, size: size)
                        for bullet in game.bullets {
                            let rect = CGRect(x: bullet.position.x - 2, y: bullet.position.y - 9,
                                              width: 4, height: 18)
                            context.fill(Path(rect), with: .color(.yellow))
                        }
                        for shot in game.enemyBullets {
                            context.fill(Path(ellipseIn: CGRect(x: shot.position.x - 3, y: shot.position.y - 6, width: 6, height: 12)), with: .color(.orange))
                        }
                        if let beam = game.beam {
                            context.fill(Path(beam), with: .color(.cyan.opacity(Int(game.elapsed * 12) % 2 == 0 ? 0.35 : 0.18)))
                            for stripe in 0..<5 {
                                let y = beam.minY + (CGFloat(stripe) * 55 + game.elapsed * 90).truncatingRemainder(dividingBy: max(1, beam.height))
                                context.stroke(Path(CGRect(x: beam.minX, y: y, width: beam.width, height: 12)), with: .color(.cyan), lineWidth: 1)
                            }
                        }
                        let displayedEnemies = game.runActive ? game.enemies : (0..<40).map {
                            Enemy(slot: $0, position: game.entrancePosition(
                                slot: $0, time: game.elapsed.truncatingRemainder(dividingBy: 13)))
                        }
                        for enemy in displayedEnemies {
                            drawShip(context: &context, at: enemy.position,
                                     size: CGSize(width: Enemy.size.width + (Int(game.elapsed * 5) % 2 == 0 ? 0 : -4), height: Enemy.size.height),
                                     color: enemy.kind == .boss ? (enemy.health == 2 ? .green : .blue) : enemy.kind == .escort ? .pink : .yellow, pointsDown: true)
                            if enemy.hasCapturedShip && game.status != .captured {
                                drawShip(context: &context, at: CGPoint(x: enemy.position.x, y: enemy.position.y + 26),
                                         size: GameViewModel.playerSize, color: .red, pointsDown: false)
                            }
                        }
                        if game.status == .playing,
                           game.invulnerability == 0 || Int(game.elapsed * 8) % 2 == 0 {
                            for offset: CGFloat in (game.dualFighter ? [-16, 16] : [0]) {
                                drawShip(context: &context, at: CGPoint(x: game.playerX + offset, y: game.playerY),
                                         size: GameViewModel.playerSize, color: .cyan, pointsDown: false)
                            }
                        }
                        if let point = game.capturedPosition {
                            var spinning = context
                            spinning.translateBy(x: point.x, y: point.y)
                            spinning.rotate(by: .radians(Double(game.elapsed * 8)))
                            drawShip(context: &spinning, at: .zero, size: GameViewModel.playerSize, color: .red, pointsDown: false)
                        }
                    }
                    .onChange(of: timeline.date) { _, date in game.tick(at: date) }
                }
                .background(.black)
                .contentShape(Rectangle())
                // A drag uses local canvas coordinates, exactly like the player.
                .gesture(DragGesture(minimumDistance: 8)
                    .onChanged { game.movePlayer(to: $0.location.x) })
                .simultaneousGesture(SpatialTapGesture().onEnded { _ in game.fire() })
                .onAppear { game.resize(to: geometry.size) }
                .onChange(of: geometry.size) { _, size in game.resize(to: size) }
                .overlay {
                    if game.status != .playing {
                        arcadeOverlay
                    } else if game.stageTime < 2 {
                        Text(game.isChallenge ? "CHALLENGING STAGE" : "STAGE \(game.stage)").foregroundStyle(.cyan)
                            .font(.system(.title2, design: .monospaced, weight: .bold))
                            .allowsHitTesting(false)
                    }
                }
                .clipped()
            }

            HStack(spacing: 16) {
                Button { game.stepPlayer(-1) } label: {
                    Image(systemName: "arrow.left").frame(width: 48, height: 44)
                }.accessibilityLabel("Move left")
                Button { game.stepPlayer(1) } label: {
                    Image(systemName: "arrow.right").frame(width: 48, height: 44)
                }.accessibilityLabel("Move right")
                Spacer(minLength: 0)
                Button { game.fire() } label: {
                    Text("FIRE").fontWeight(.black).frame(width: 70, height: 44)
                }
            }
            .buttonStyle(.bordered).tint(.cyan)
            .disabled(game.status != .playing)
            .padding()
            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<game.reserveLives, id: \.self) { _ in
                        Image(systemName: "paperplane.fill").foregroundStyle(.cyan)
                    }
                }
                .accessibilityLabel("\(game.reserveLives) reserve ships")
                Spacer()
                Button { game.soundEnabled.toggle() } label: {
                    Image(systemName: game.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }.accessibilityLabel(game.soundEnabled ? "Mute sound" : "Enable sound")
                Text("CREDIT \(String(format: "%02d", game.credits))")
                Button { game.insertCoin() } label: {
                    Image(systemName: "plus").font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.yellow.opacity(0.2), in: Circle())
                        .overlay(Circle().stroke(.yellow, lineWidth: 2))
                }
                .foregroundStyle(.yellow)
                .accessibilityLabel("Insert free coin")
            }
            .font(.system(.caption, design: .monospaced, weight: .bold))
            .padding(.horizontal).padding(.bottom, 8)
        }
        .foregroundStyle(.white)
        .background(.black)
        .preferredColorScheme(.dark)
        .onAppear { game.onSound = { event in audio.play(event) } }
        .onChange(of: scenePhase) { _, _ in game.resetClock() }
    }

    private var arcadeOverlay: some View {
        VStack(spacing: 22) {
            Text("GALAGA").font(.system(size: 38, weight: .black, design: .monospaced))
                .foregroundStyle(.yellow)
            if game.status == .stageComplete {
                Text(game.isChallenge ? "CHALLENGE RESULTS" : "STAGE \(game.stage) CLEAR")
                    .foregroundStyle(.cyan)
                if game.isChallenge {
                    Text("HITS \(game.challengeHits) / 40")
                    Text("BONUS \(game.challengeBonus)")
                    if game.challengeHits == 40 { Text("PERFECT!").foregroundStyle(.yellow) }
                }
                Text("NEXT STAGE...")
            } else if game.status == .captured {
                Text("FIGHTER CAPTURED").foregroundStyle(.red)
                Text("DESTROY ITS CARRIER TO RESCUE IT")
                    .font(.system(size: 11, design: .monospaced))
            } else if game.status == .nameRegistration {
                Text("NEW HIGH SCORE").foregroundStyle(.cyan)
                TextField("INITIALS", text: $initials)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .multilineTextAlignment(.center).frame(width: 120)
                    .textFieldStyle(.roundedBorder)
                Button("REGISTER") { game.registerName(initials) }
                    .buttonStyle(.borderedProminent)
            } else if game.status == .ready {
                Text("PUSH START BUTTON").foregroundStyle(.cyan)
                Button("START") { game.startGame() }
                    .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                VStack(spacing: 8) {
                    Text("1ST BONUS FOR 20,000 PTS")
                    Text("2ND BONUS FOR 70,000 PTS")
                    Text("AND FOR EVERY 70,000 PTS")
                }.font(.system(size: 12, weight: .bold, design: .monospaced))
            } else {
                Text("GAME OVER")
                    .foregroundStyle(.red)
                Text("\(game.highScoreName)  \(String(format: "%06d", game.highScore))")
                if game.credits > 0 {
                    Button("PUSH START BUTTON") { game.startGame() }
                        .buttonStyle(.borderedProminent).tint(.cyan).foregroundStyle(.black)
                } else {
                    Text("INSERT COIN").foregroundStyle(.yellow)
                }
            }
        }
        .font(.system(.headline, design: .monospaced, weight: .bold))
        .multilineTextAlignment(.center)
        .padding(18)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    }

    private func drawStars(context: inout GraphicsContext, size: CGSize) {
        // Deterministic positions prevent stars from flickering on every tick.
        for index in 0..<65 {
            let x = CGFloat((index * 73 + 19) % 997) / 997 * size.width
            let y = (CGFloat((index * 137 + 47) % 991) / 991 * size.height + game.elapsed * CGFloat(16 + index % 3 * 10)).truncatingRemainder(dividingBy: max(1, size.height))
            context.fill(Path(CGRect(x: x, y: y, width: 2, height: 2)),
                         with: .color(index % 3 == 0 ? .cyan.opacity(0.5) : .white.opacity(0.4)))
        }
    }

    private func drawShip(context: inout GraphicsContext, at center: CGPoint,
                          size: CGSize, color: Color, pointsDown: Bool) {
        let direction: CGFloat = pointsDown ? -1 : 1
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + x * size.width, y: center.y + y * size.height * direction)
        }
        var ship = Path()
        ship.move(to: point(0, -0.5))
        for vertex in [point(0.16, -0.1), point(0.5, 0.3), point(0.5, 0.5),
                       point(0.14, 0.32), point(0, 0.5), point(-0.14, 0.32),
                       point(-0.5, 0.5), point(-0.5, 0.3), point(-0.16, -0.1)] {
            ship.addLine(to: vertex)
        }
        ship.closeSubpath()
        context.fill(ship, with: .color(color))
        context.fill(Path(CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 8)),
                     with: .color(.white))
    }
}

#Preview { GameView() }
