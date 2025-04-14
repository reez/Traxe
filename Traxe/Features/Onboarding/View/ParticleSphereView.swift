import SwiftUI

struct ParticleSphereView: View {
    @State private var particles: [Particle] = ParticleSphereView.generateInitialParticles(
        count: 500,
        radius: 1.0
    )
    let particleColor: Color

    @State private var rotationAngle: Angle = .zero

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvasContext, size in

                let currentTime = context.date.timeIntervalSinceReferenceDate
                let angularVelocity: Double = 0.5

                let currentAngle = Angle.radians(currentTime * angularVelocity)

                let drawRadius = min(size.width, size.height) / 2

                for (_, particle) in particles.enumerated() {
                    let rotatedX =
                        particle.x * cos(currentAngle.radians) + particle.z
                        * sin(currentAngle.radians)
                    let rotatedZ =
                        -particle.x * sin(currentAngle.radians) + particle.z
                        * cos(currentAngle.radians)

                    let scaleFactor = (rotatedZ + 1.0) / 2.0
                    let projectedX = rotatedX * drawRadius * scaleFactor
                    let projectedY = particle.y * drawRadius * scaleFactor

                    let viewX = size.width / 2 + projectedX
                    let viewY = size.height / 2 + projectedY

                    let pointSize = max(0.5, 2.0 * scaleFactor)
                    let opacity = max(0.2, scaleFactor)

                    guard viewX.isFinite, viewY.isFinite, pointSize > 0, opacity > 0 else {
                        continue
                    }

                    let pointRect = CGRect(
                        x: viewX - pointSize / 2,
                        y: viewY - pointSize / 2,
                        width: pointSize,
                        height: pointSize
                    )

                    canvasContext.fill(
                        Circle().path(in: pointRect),
                        with: .color(particleColor.opacity(opacity))
                    )
                }

            }
            .drawingGroup()
        }
    }

    static func generateInitialParticles(count: Int, radius: Double) -> [Particle] {
        return (0..<count).map { _ in
            let theta = Double.random(in: 0...(2 * .pi))
            let phi = acos(Double.random(in: -1...1))
            let radiusMultiplier = 1.0

            let x = radius * sin(phi) * cos(theta) * radiusMultiplier
            let y = radius * sin(phi) * sin(theta) * radiusMultiplier
            let z = radius * cos(phi) * radiusMultiplier

            return Particle(x: x, y: y, z: z)
        }
    }
}

#Preview {
    ParticleSphereView(particleColor: .white)
        .background(Color.black)
        .frame(width: 300, height: 300)
}
