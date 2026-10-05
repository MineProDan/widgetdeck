import SwiftUI

/// Settings → About → "A hobby project": states that Widgetdeck is a free, unpaid personal project.
/// Keep it in line with the app being completely free (no income of any kind).
struct HobbyProjectView: View {
    var body: some View {
        Form {
            Section {
                Text("Widgetdeck is a personal hobby project. I make it in my free time because I enjoy building things for my own home screen, and I hope it's useful for yours.")
            }
            Section {
                point("No income", "Widgetdeck earns no money or revenue of any kind.", systemImage: "dollarsign.circle")
                point("No payments, ever", "No in-app purchases, subscriptions, ads, tips, donations, sponsorships or affiliate links. Every feature is free for everyone.", systemImage: "cart.badge.minus")
                point("Not employment", "I build it in my own free time. It isn't a job, a business or work for anyone. No one pays me, hires me or directs the work.", systemImage: "person.crop.circle.badge.xmark")
                point("Strictly a hobby", "It won't be turned into a source of revenue in the future. It stays a free, non-commercial project.", systemImage: "heart")
                point("No data sold or shared", "There are no accounts, no analytics and no ads, so there's nothing to sell. Your data stays on your iPhone and in your own iCloud.", systemImage: "lock")
            } header: {
                Text("What that means")
            }
            Section {
                Text("Widgetdeck is provided free and as is, without warranty. Feedback is welcome through the support page, but there's no paid support, and I don't accept payment or gifts for the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("A hobby project")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func point(_ title: String, _ detail: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
