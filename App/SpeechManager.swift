import Foundation
import AVFoundation
import Combine

struct ChapterItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let url: String
}

class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    
    @Published var chapters: [ChapterItem] = []
    @Published var currentChapterIndex: Int = 0
    @Published var sentences: [String] = []
    @Published var currentSentenceIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var statusMessage: String = "Sẵn sàng"
    @Published var speechRate: Float = 0.5

    override init() {
        super.init()
        synthesizer.delegate = self
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("Lỗi AudioSession: \(error.localizedDescription)")
        }
    }

    func fetchTableOfContents(from urlString: String) {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            statusMessage = "URL không hợp lệ"
            return
        }
        statusMessage = "Đang quét danh sách chương..."
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { self.statusMessage = "Không thể tải trang mục lục" }
                return
            }

            let pattern = "<a[^>]+href=[\"']([^\"']+)[\"'][^>]*>([\\s\\S]*?)<\\/a>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
            
            let nsString = html as NSString
            let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
            
            var foundChapters: [ChapterItem] = []
            var seenUrls = Set<String>()

            for match in matches {
                var rawLink = nsString.substring(with: match.range(at: 1))
                let title = nsString.substring(with: match.range(at: 2))
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if title.lowercased().contains("chương") || title.lowercased().contains("chuong") {
                    if !rawLink.starts(with: "http"), let baseURL = URL(string: urlString), let absolute = URL(string: rawLink, relativeTo: baseURL) {
                        rawLink = absolute.absoluteString
                    }
                    if !seenUrls.contains(rawLink) {
                        seenUrls.insert(rawLink)
                        foundChapters.append(ChapterItem(title: title, url: rawLink))
                    }
                }
            }

            DispatchQueue.main.async {
                if foundChapters.isEmpty {
                    self.statusMessage = "Không tìm thấy chương nào"
                } else {
                    self.chapters = foundChapters
                    self.statusMessage = "Đã tìm thấy \(foundChapters.count) chương"
                }
            }
        }.resume()
    }

    func loadAndPlayChapter(index: Int) {
        guard index >= 0 && index < chapters.count else { return }
        currentChapterIndex = index
        let chapter = chapters[index]
        statusMessage = "Đang tải: \(chapter.title)..."
        stop()

        guard let url = URL(string: chapter.url) else { return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async { self.statusMessage = "Lỗi khi tải nội dung" }
                return
            }

            var content = html
            if let startRange = html.range(of: "class=\"chapter-c\""),
               let divEnd = html[startRange.upperBound...].range(of: "</div>") {
                content = String(html[startRange.upperBound..<divEnd.lowerBound])
            }

            let clean = content
                .replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<p[^>]*>", with: "\n", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ")

            DispatchQueue.main.async {
                self.setupSentences(from: clean)
                self.play()
            }
        }.resume()
    }

    private func setupSentences(from text: String) {
        let clean = text.replacingOccurrences(of: "\r", with: "")
        let rawParts = clean.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        self.sentences = rawParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
        self.currentSentenceIndex = 0
        if let current = chapters[safe: currentChapterIndex] {
            self.statusMessage = "Đang đọc: \(current.title)"
        }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard !sentences.isEmpty, currentSentenceIndex < sentences.count else { return }
        isPlaying = true
        speakCurrent()
    }

    func pause() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isPlaying = false
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        currentSentenceIndex = 0
    }

    func jumpToSentence(_ index: Int) {
        guard index >= 0 && index < sentences.count else { return }
        synthesizer.stopSpeaking(at: .immediate)
        currentSentenceIndex = index
        if isPlaying { speakCurrent() }
    }

    private func speakCurrent() {
        guard currentSentenceIndex < sentences.count else {
            goToNextChapter()
            return
        }
        let utterance = AVSpeechUtterance(string: sentences[currentSentenceIndex])
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        utterance.rate = speechRate
        synthesizer.speak(utterance)
    }

    func goToNextChapter() {
        if currentChapterIndex + 1 < chapters.count {
            loadAndPlayChapter(index: currentChapterIndex + 1)
        } else {
            stop()
            statusMessage = "Đã đọc hết các chương"
        }
    }

    func goToPreviousChapter() {
        if currentChapterIndex - 1 >= 0 {
            loadAndPlayChapter(index: currentChapterIndex - 1)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard isPlaying else { return }
        DispatchQueue.main.async {
            self.currentSentenceIndex += 1
            self.speakCurrent()
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
