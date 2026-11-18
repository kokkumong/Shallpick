import SwiftUI

struct DemoPhotoPicker: View {
    var onAdd: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("샘플 사진 추가").font(.title2.bold())
                Spacer()
                Button("닫기") { dismiss() }
            }
            Text("시연에서는 기기 보관함 대신 샘플 사진 3장을 폴더에 추가해요.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(1...3, id: \.self) { index in
                    Image("DemoPhoto\(index)").resizable().scaledToFill()
                        .frame(width: 96, height: 128).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Button("샘플 사진 3장 추가", action: onAdd)
                .font(.headline).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.black800, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("demo.addPhotos")
            Spacer()
        }
        .padding(24).padding(.top, 12)
    }
}
