import SwiftUI

struct ContentView: View {
    @StateObject private var speech = SpeechManager()
    @State private var tocURL: String = ""
    @State private var showChapterSheet: Bool = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack {
                        TextField("Dán link mục lục truyện...", text: $tocURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        Button("Lấy mục lục") {
                            speech.fetchTableOfContents(from: tocURL)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    
                    HStack {
                        Text(speech.statusMessage)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        Spacer()
                        if !speech.chapters.isEmpty {
                            Button("Mục lục (\(speech.chapters.count))") {
                                showChapterSheet = true
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(speech.sentences.indices, id: \.self) { idx in
                                Text(speech.sentences[idx])
                                    .font(.system(size: 17))
                                    .padding(8)
                                    .background(speech.currentSentenceIndex == idx ? Color.blue.opacity(0.25) : Color.clear)
                                    .cornerRadius(6)
                                    .id(idx)
                                    .onTapGesture {
                                        speech.jumpToSentence(idx)
                                    }
                            }
                        }
                        .padding()
                    }
                    .onReceive(speech.$currentSentenceIndex) { newIndex in
                        withAnimation {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }

                VStack(spacing: 10) {
                    HStack {
                        Text("Tốc độ: \(String(format: "%.1f", speech.speechRate * 2))x")
                            .font(.footnote)
                        Slider(value: $speech.speechRate, in: 0.3...0.8)
                    }

                    HStack(spacing: 36) {
                        Button(action: { speech.goToPreviousChapter() }) {
                            Image(systemName: "backward.end.fill").font(.title2)
                        }

                        Button(action: { speech.togglePlayPause() }) {
                            Image(systemName: speech.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 54))
                                .foregroundColor(.blue)
                        }

                        Button(action: { speech.goToNextChapter() }) {
                            Image(systemName: "forward.end.fill").font(.title2)
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.systemBackground).shadow(radius: 4))
            }
            .navigationTitle("Trình Đọc Truyện")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showChapterSheet) {
                NavigationView {
                    List(speech.chapters.indices, id: \.self) { idx in
                        Button(action: {
                            showChapterSheet = false
                            speech.loadAndPlayChapter(index: idx)
                        }) {
                            HStack {
                                Text(speech.chapters[idx].title)
                                    .foregroundColor(speech.currentChapterIndex == idx ? .blue : .primary)
                                Spacer()
                                if speech.currentChapterIndex == idx {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .navigationTitle("Danh sách chương")
                    .navigationBarItems(trailing: Button("Đóng") { showChapterSheet = false })
                }
            }
        }
    }
}
