import SwiftUI

struct MediaPosterView: View {
    @EnvironmentObject private var appModel: AppModel
    let item: MediaItem
    var width: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottom) {
                AsyncImage(url: appModel.imageURL(for: item, maxWidth: Int(width * 2))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ZStack {
                            placeholder
                            ProgressView()
                        }
                    }
                }
                .frame(width: width, height: width * 1.48)
                .clipped()

                if let progress = item.progress, progress > 0, progress < 0.99 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.cyan)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(item.name)
                .font(.headline)
                .lineLimit(1)
            Text(item.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.gray.opacity(0.35), .gray.opacity(0.12)], startPoint: .top, endPoint: .bottom)
            Image(systemName: item.isSeries ? "rectangle.stack.fill" : "film.fill")
                .font(.system(size: 54))
                .foregroundStyle(.secondary)
        }
    }
}

struct MediaShelf: View {
    let title: String
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.title.bold())
                .padding(.horizontal, 70)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 30) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            MediaPosterView(item: item)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 70)
                .padding(.vertical, 24)
            }
        }
    }
}

struct LibraryCard: View {
    @EnvironmentObject private var appModel: AppModel
    let library: MediaLibrary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: appModel.imageURL(for: library, maxWidth: 900)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.cyan.opacity(0.35), .blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(minHeight: 220)
            .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Text(library.name)
                    .font(.title2.bold())
                if let count = library.childCount {
                    Text("\(count) 项")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
        .frame(minWidth: 390, minHeight: 220)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }
}

struct LoadingOverlay: View {
    let text: String

    var body: some View {
        HStack(spacing: 18) {
            ProgressView()
            Text(text)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
