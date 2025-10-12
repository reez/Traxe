import SwiftUI
import simd

struct ParticleSphereView: View {
    @State private var particles: [Particle] = ParticleSphereView.generateInitialParticles(
        count: 1800,
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

                // Light source direction (normalized vector pointing from top-front)
                let lightDirection = simd_normalize(simd_double3(x: 0.3, y: -0.5, z: 1.0))

                for (_, particle) in particles.enumerated() {
                    let rotatedX =
                        particle.x * cos(currentAngle.radians) + particle.z
                        * sin(currentAngle.radians)
                    let rotatedZ =
                        -particle.x * sin(currentAngle.radians) + particle.z
                        * cos(currentAngle.radians)

                    // Calculate lighting based on particle normal (position on sphere surface)
                    let normal = simd_normalize(
                        simd_double3(x: rotatedX, y: particle.y, z: rotatedZ)
                    )
                    let lightIntensity = max(0.0, simd_dot(normal, lightDirection))

                    // Enhanced lighting calculation with ambient + directional
                    let ambientLight = 0.3
                    let lighting = ambientLight + (1.0 - ambientLight) * pow(lightIntensity, 1.5)

                    let scaleFactor = (rotatedZ + 1.0) / 2.0
                    let projectedX = rotatedX * drawRadius * scaleFactor
                    let projectedY = particle.y * drawRadius * scaleFactor

                    let viewX = size.width / 2 + projectedX
                    let viewY = size.height / 2 + projectedY

                    // Crisp particle sizing with moderate variation
                    let baseSize = 1.0 + 1.8 * scaleFactor
                    let pointSize = max(0.8, min(2.5, baseSize * lighting))

                    // More dramatic opacity based on depth and lighting
                    let depthOpacity = pow(scaleFactor, 0.7)
                    let opacity = max(0.2, min(1.0, depthOpacity * lighting * 1.3))

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

#Preview("Dark Mode") {
    ParticleSphereView(particleColor: .white)
        .background(Color.black)
        .frame(width: 300, height: 300)
}

#Preview("Light Mode") {
    ParticleSphereView(particleColor: .black)
        .background(Color.white)
        .frame(width: 300, height: 300)
}

#Preview("Adaptive") {
    ParticleSphereView(particleColor: .primary)
        .frame(width: 300, height: 300)
}
