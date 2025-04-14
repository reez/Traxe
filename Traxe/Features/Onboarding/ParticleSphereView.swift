import SwiftUI

struct Particle: Identifiable {
    let id = UUID()
    // Position in 3D space (normalized -1 to 1 initially)
    var x: Double
    var y: Double
    var z: Double
}

struct ParticleSphereView: View {
    // Initialize @State directly with generated particles
    @State private var particles: [Particle] = ParticleSphereView.generateInitialParticles(
        count: 500,
        radius: 1.0
    )
    let particleColor: Color

    // Rotation state
    @State private var rotationAngle: Angle = .zero

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { canvasContext, size in
                // --- Restore Original Particle Drawing Logic ---

                let currentTime = context.date.timeIntervalSinceReferenceDate
                let angularVelocity: Double = 0.5  // Radians per second

                // --- Simple Rotation ---
                // Update rotation based on time - can make this more complex
                let currentAngle = Angle.radians(currentTime * angularVelocity)

                let drawRadius = min(size.width, size.height) / 2  // Adjust drawing size

                for (_, particle) in particles.enumerated() {  // Use enumerated to limit prints
                    // --- Basic Rotation (around Y axis) ---
                    let rotatedX =
                        particle.x * cos(currentAngle.radians) + particle.z
                        * sin(currentAngle.radians)
                    let rotatedZ =
                        -particle.x * sin(currentAngle.radians) + particle.z
                        * cos(currentAngle.radians)

                    // --- Simple Projection ---
                    let scaleFactor = (rotatedZ + 1.0) / 2.0  // 0.0 to 1.0
                    let projectedX = rotatedX * drawRadius * scaleFactor
                    let projectedY = particle.y * drawRadius * scaleFactor  // Using original y

                    // --- Center on Canvas ---
                    let viewX = size.width / 2 + projectedX
                    let viewY = size.height / 2 + projectedY

                    // --- Draw Particle ---
                    let pointSize = max(0.5, 2.0 * scaleFactor)
                    let opacity = max(0.2, scaleFactor)

                    // --- Check for invalid values before drawing ---
                    guard viewX.isFinite, viewY.isFinite, pointSize > 0, opacity > 0 else {
                        // if index < 5 { print("Particle \(index): Invalid drawing values, skipping.") } // Remove DEBUG print
                        continue  // Skip drawing if values are bad
                    }

                    let pointRect = CGRect(
                        x: viewX - pointSize / 2,
                        y: viewY - pointSize / 2,
                        width: pointSize,
                        height: pointSize
                    )

                    // --- Use fill for solid dots ---
                    canvasContext.fill(
                        Circle().path(in: pointRect),
                        with: .color(particleColor.opacity(opacity))
                    )
                }

            }
            // Use .drawingGroup() for potentially better performance with many elements
            .drawingGroup()  // Re-enable drawingGroup
        }
        // Optional: Add gestures for interactive rotation
        // .gesture(...)
    }

    // Static function to generate initial particles
    static func generateInitialParticles(count: Int, radius: Double) -> [Particle] {
        return (0..<count).map { _ in
            // Generate random points on the surface of a sphere
            let theta = Double.random(in: 0...(2 * .pi))  // Azimuthal angle
            let phi = acos(Double.random(in: -1...1))  // Polar angle (acos ensures uniform distribution)
            let radiusMultiplier = 1.0  // For surface only

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
