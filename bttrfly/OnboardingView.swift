import SwiftUI

// MARK: - Shared onboarding UI
struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack { content }
            .padding(.vertical, 32)
            .padding(.horizontal, 36)
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .fill(.thickMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.35),
                                             .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom),
                                lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 0)
    }
}


private struct Bullet: View {
    var text: String
    var icon: String
    var body: some View {
        Label { Text(text) } icon: {
            Image(systemName: icon).frame(width: 14)
        }
        .font(Font.custom("Pretendard", size: 15)).fontWeight(.semibold)
    }
}


struct OnboardingView: View {
    enum Step { case welcome, chooseFolder }
    @State private var step: Step = .welcome
    @State private var isBackHover = false        // hover state for back arrow
    @Environment(\.colorScheme) private var colorScheme

    /// Called when the user taps “Select Folder…”
    var pickFolder: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack {
                Spacer(minLength: 0)          // push content toward vertical center
                Group {
                    switch step {
                    case .welcome:
                        WelcomeCard {
                            withAnimation(.easeInOut) { step = .chooseFolder }
                        }
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom),
                                removal: .opacity
                            )
                        )

                    case .chooseFolder:
                        FolderCard(pickFolder: pickFolder)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom),
                                    removal: .opacity
                                )
                            )
                    }
                }
                Spacer(minLength: 0)
            }
            // ───────── Back arrow (only on page 2) ─────────
            if step == .chooseFolder {
                Button(action: {
                    withAnimation(.easeInOut) { step = .welcome }
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(10)                   // larger tap target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundColor(
                    (colorScheme == .dark ? Color.white : Color.black)
                        .opacity(isBackHover ? 0.9 : 0.6)
                )
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isBackHover = hovering
                    }
                }
                .padding(.top, 3)
                .padding(.leading, 1)                // snug to top‑left corner
            }
        }   // end ZStack
        .padding(.vertical, 32)
        .padding(.horizontal, 36)
        .frame(width: 400, height: 550)            // size first
        .background(                               // then draw rounded backdrop
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    (colorScheme == .dark
                        ? Color(white: 0.12, opacity: 0.55)
                        : Color.white.opacity(0.25)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))   // mask everything
        // Subtle white halo glow behind the panel
        .environment(\.font, Font.custom("Pretendard", size: 15))
        .onAppear { dumpPretendardFonts() }
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var cs
    func makeBody(configuration: Configuration) -> some View {
        // Background color switches: white in Dark Mode, dark‑gray in Light Mode
        let bg = cs == .dark ? Color.white : Color(white: 0.15)
        let fg = cs == .dark ? Color.black : Color.white

        configuration.label
            .font(Font.custom("Pretendard", size: 15)).fontWeight(.semibold)
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(bg.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Cards
private struct WelcomeCard: View {
    var next: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Image("bttrfly-white")          // ← 바로 이 줄이 추가된 부분
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.primary)
                    .frame(width: 35, height: 32)
                    .padding(.bottom, 23)

            Text("Ideas Don’t Queue")
                .font(Font.custom("Pretendard", size: 23)).fontWeight(.black)
                .tracking(-0.8)          // tighter letter‑spacing
            

            Text(
                "Hey, Markdown nerd!\n\nNeed to jot something before the idea evaporates?\nA hotkey opens a note faster than your latte order."
            )
                .fixedSize(horizontal: false, vertical: true)   // prevent truncation, allow full wrap
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(Font.custom("Pretendard", size: 14))
                .padding(.vertical, 6)
                .padding(.top, 20)
                .lineSpacing(5)                // widen line height

            VStack(alignment: .leading, spacing: 6) {
                Bullet(text: "Local Only", icon: "lock")
                Bullet(text: "Pure Markdown", icon: "number")
                Bullet(text: "Keyboard‑first flow", icon: "command")
                Bullet(text: "Plug‑and‑play. Just add your vault", icon: "square.fill.on.square.fill")
            }
            .padding(.vertical, 25)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("More goodies are on the way!ㅡAI sth :)")
                .font(Font.custom("Pretendard", size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text("Found a bug—or itching to unload some creative profanity? Smash the email in Settings and let it rip.")
                .fixedSize(horizontal: false, vertical: true)   // allow full wrap, avoid truncation
                .font(Font.custom("Pretendard", size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .lineSpacing(5)                // widen line height
            

            Button("Let's set the folder", action: next)
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .padding(.vertical, 20)
        }   // end VStack
    }       // end body
}           // end struct

private struct FolderCard: View {
    var pickFolder: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Image("bttrflynfolder")
                .resizable()
                .scaledToFit()                       // keep aspect‑ratio
                .frame(width: 220, height: 148)      // bigger image
                .padding(.top, 85)
            
            Spacer(minLength: 0)            // push everything below downward

            Text("Choose your home base")
                .font(Font.custom("Pretendard", size: 20)).fontWeight(.semibold)
                .padding(.top, 10)
                .padding(.bottom, 20)

            Text("Bttrfly stores notes in this folder.\nYou can change it anytime in settings.")
                .font(Font.custom("Pretendard", size: 15))
                .multilineTextAlignment(.center)
                .padding(.bottom, 3)
                .lineSpacing(5)
            
            Spacer(minLength: 0)        // ← pushes the button toward the bottom


            Button("Select Folder…", action: pickFolder)
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .padding(.vertical, 20)
        }
        .frame(maxHeight: .infinity, alignment: .top)   // allow spacer to expand
    } // end body
}           // end struct

// MARK: - Debug helper
/// Prints all Pretendard PostScript names currently registered in the bundle.
private func dumpPretendardFonts() {
    let names = CTFontManagerCopyAvailablePostScriptNames() as! [String]
    let pret = names.filter { $0.localizedCaseInsensitiveContains("Pretendard") }
    print("🅿️ Pretendard variants found →", pret)
}
