import SwiftUI

/// 새 폴더 / 코드로 참여하기 / 프로필(닉네임) 수정 입력 카드
/// Figma: 새폴더 (246:5269), 코드입력 (246:5278)
struct FolderInputDialog: View {
    enum Kind {
        case create
        case join
        case nickname

        var title: String {
            switch self {
            case .create: "새 폴더"
            case .join: "코드로 참여하기"
            case .nickname: "프로필 수정"
            }
        }

        var placeholder: String {
            switch self {
            case .create: "폴더 이름을 입력해주세요"
            case .join: "코드입력"
            case .nickname: "닉네임을 입력해주세요"
            }
        }

        /// 입력할 수 있는 최대 글자 수 (nil = 제한 없음)
        var maxLength: Int? {
            switch self {
            case .create: FolderRepository.maxNameLength
            case .join: nil
            case .nickname: ProfileRepository.maxNicknameLength
            }
        }

        var failureMessage: String {
            switch self {
            case .create: "폴더를 만들지 못했어요. 잠시 후 다시 시도해 주세요."
            case .join: "참여하지 못했어요. 잠시 후 다시 시도해 주세요."
            case .nickname: "닉네임을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요."
            }
        }
    }

    let kind: Kind
    var initialText = ""
    var onCancel: () -> Void
    /// 실패하면 에러 메시지를 카드 아래에 보여줍니다.
    var onSubmit: (String) async throws -> Void

    @State private var text = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture { if !isSubmitting { onCancel() } }
                .accessibilityHidden(true)

            card
                .padding(.horizontal, 12)
                .padding(.top, 151.5)
        }
        .ignoresSafeArea(.keyboard)
        .onAppear {
            text = initialText
            isFocused = true
        }
    }

    private var card: some View {
        VStack(spacing: 25) {
            HStack {
                CircleIconButton(icon: .iconClose, accessibilityLabel: "닫기", action: onCancel)
                    .disabled(isSubmitting)

                Spacer()

                Text(kind.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.black)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                CircleIconButton(icon: .iconCheck, style: .filled, accessibilityLabel: "확인", action: submit)
                    .disabled(trimmed.isEmpty || isSubmitting)
                    .opacity(trimmed.isEmpty ? 0.4 : 1)
                    .overlay {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                field

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }
            }
        }
        .padding(20)
        .background(Color.black50, in: RoundedRectangle(cornerRadius: 36))
        .shallpickShadow(blur: 20)
        .animation(.snappy(duration: 0.2), value: errorMessage)
    }

    private var field: some View {
        TextField(
            "",
            text: $text,
            prompt: Text(kind.placeholder).foregroundStyle(Color.black400)
        )
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Color.black800)
        .focused($isFocused)
        .submitLabel(kind == .join ? .join : .done)
        .onSubmit(submit)
        .textInputAutocapitalization(kind == .join ? .characters : .sentences)
        .autocorrectionDisabled()
        .onChange(of: text) { _, newValue in
            errorMessage = nil
            if let maxLength = kind.maxLength, newValue.count > maxLength {
                text = String(newValue.prefix(maxLength))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(.white, in: Capsule())
        .shallpickShadow(blur: 20)
    }

    private func submit() {
        guard !trimmed.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                try await onSubmit(trimmed)
            } catch let error as FolderRepository.FolderError {
                errorMessage = error.localizedDescription
            } catch {
                print("[Folder] \(kind) 실패:", error)
                errorMessage = kind.failureMessage
            }
        }
    }
}

#Preview("새 폴더") {
    FolderInputDialog(kind: .create, onCancel: {}, onSubmit: { _ in })
        .background(Color.black50)
}

#Preview("코드 입력") {
    FolderInputDialog(kind: .join, onCancel: {}, onSubmit: { _ in
        throw FolderRepository.FolderError.invalidInviteCode
    })
    .background(Color.black50)
}
