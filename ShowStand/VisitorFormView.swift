import Combine
import SwiftUI
import SwiftData

/// Sheet over the display. Its state is thrown away every time it closes,
/// so nothing a visitor typed is ever visible to the next one.
/// Name, email and phone deliberately have no textContentType: it would make iOS suggest
/// the device owner's own contact details to visitors.
struct VisitorFormView: View {
    let booth: Booth

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var showErrors = false
    @State private var submitted = false
    @FocusState private var focus: Field?

    private enum Field { case name, email, phone }

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPhone: String { phone.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameValid: Bool { !trimmedName.isEmpty }
    private var emailValid: Bool { Validate.isValidEmail(trimmedEmail) }
    private var accent: Color { Color(hex: booth.accentColor) }
    private var hasOffer: Bool { !booth.offerText.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if submitted { thanks } else { form }
            }
            .toolbar {
                if !submitted {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
        .tint(accent)
        .onAppear { ActivityTracker.touch() }
        .onChange(of: [name, email, phone]) { ActivityTracker.touch() }
        .onChange(of: focus) { ActivityTracker.touch() }
        .onReceive(tick) { _ in
            if !submitted && ActivityTracker.idleSeconds >= Timing.visitorFormReset { dismiss() }
        }
        .task(id: submitted) {
            guard submitted else { return }
            try? await Task.sleep(for: .seconds(4))
            dismiss()
        }
    }

    private var form: some View {
        Form {
            Section {
                Text(hasOffer ? booth.offerText : "Stay in touch")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(accent)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .name)
                    .onSubmit { focus = .email }
                if showErrors && !nameValid {
                    Text("Please enter your name.").errorStyle()
                }
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .phone }
                if showErrors && !emailValid {
                    Text("Please enter a valid email.").errorStyle()
                }
                TextField("Phone (optional)", text: $phone)
                    .keyboardType(.phonePad)
                    .focused($focus, equals: .phone)
            }
            .font(.title3)

            Section {
                Button(action: submit) {
                    Text(hasOffer ? "Send it to me" : "Stay in touch")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(accent.readableForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text("Your info goes only to \(booth.name) so they can follow up. It stays on this device.")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
    }

    private var thanks: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(accent)
            Text("Thanks!")
                .font(.largeTitle.bold())
            Text(hasOffer ? booth.offerText : "We'll be in touch soon.")
                .font(.title2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }

    private func submit() {
        guard nameValid, emailValid else {
            showErrors = true
            focus = nameValid ? .email : .name
            return
        }
        let lead = Lead(name: trimmedName, email: trimmedEmail, phone: trimmedPhone.isEmpty ? nil : trimmedPhone)
        context.insert(lead)
        lead.booth = booth
        try? context.save()
        focus = nil
        name = ""
        email = ""
        phone = ""
        withAnimation { submitted = true }
    }
}

private extension Text {
    func errorStyle() -> some View {
        font(.footnote).foregroundStyle(.red)
    }
}
