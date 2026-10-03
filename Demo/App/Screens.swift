import SwiftUI
import MapKit
import WebKit
import AVKit
import Nitpick

struct CheckoutScreen: View {
    @State private var name = ""
    @State private var password = ""
    @State private var card = "4242 4242 4242 4242"

    var body: some View {
        Form {
            Section("Account") {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("checkout.name")
                    .nitpickElement("checkout.name_field")
                SecureField("Password", text: $password)
                    .accessibilityIdentifier("checkout.password")
            }
            Section("Payment") {
                TextField("Card number", text: $card)
                    .accessibilityIdentifier("checkout.card")
                    .nitpickMask()
            }
            Section {
                Button("Pay 9,99") {}
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("checkout.pay")
                    .nitpickElement("checkout.pay_button")
            }
        }
        .navigationTitle("Checkout")
        .nitpickScreen("Checkout")
    }
}

struct SheetScreen: View {
    @State private var showing = false

    var body: some View {
        VStack(spacing: 20) {
            Text("A screen with a sheet").font(.title3)
            Button("Open sheet") { showing = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("sheet.open")
                .nitpickElement("sheet.open_button")
            Button("Bottom button below the sheet") {}
                .accessibilityIdentifier("sheet.below")
                .nitpickElement("sheet.below_button")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Sheet")
        .nitpickScreen("Sheet host")
        .sheet(isPresented: $showing) {
            VStack(spacing: 24) {
                Text("Go further").font(.title2.bold())
                Button("Upgrade now") { showing = false }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("sheet.upgrade")
                    .nitpickElement("sheet.upgrade_button")
                Button("Not now") { showing = false }
                    .accessibilityIdentifier("sheet.notnow")
                    .nitpickElement("sheet.notnow_button")
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .presentationDetents([.medium])
            .nitpickScreen("Upgrade sheet")
        }
    }
}

struct MapScreen: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )))
            .accessibilityIdentifier("map.view")
            .nitpickElement("map.view")
            Button("Recenter") {}
                .buttonStyle(.borderedProminent)
                .padding()
                .accessibilityIdentifier("map.recenter")
                .nitpickElement("map.recenter_button")
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .nitpickScreen("Map")
    }
}

struct DemoWebView: UIViewRepresentable {
    static let html = """
    <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <style>body{font-family:-apple-system;margin:0;padding:24px;background:#fff7e0}
    h1{color:#c2410c}.box{height:90px;margin:14px 0;border-radius:12px;color:#fff;font-size:22px;display:flex;align-items:center;justify-content:center}</style></head>
    <body><h1>WEB CONTENT</h1><p>This page is local HTML inside a WKWebView.</p>
    <div class="box" style="background:#16a34a">GREEN BOX</div>
    <div class="box" style="background:#2563eb">BLUE BOX</div>
    <div class="box" style="background:#9333ea">PURPLE BOX</div></body></html>
    """

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.loadHTMLString(Self.html, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct WebScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            DemoWebView()
                .accessibilityIdentifier("web.view")
                .nitpickElement("web.view")
            Button("Native button under the web page") {}
                .padding()
                .accessibilityIdentifier("web.native")
                .nitpickElement("web.native_button")
        }
        .navigationTitle("Web page")
        .navigationBarTitleDisplayMode(.inline)
        .nitpickScreen("Web page")
    }
}

struct VideoScreen: View {
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 16) {
            if let player {
                VideoPlayer(player: player)
                    .frame(height: 360)
                    .accessibilityIdentifier("video.player")
                    .nitpickElement("video.player")
            } else {
                ProgressView().frame(height: 360)
            }
            Button("Native button under the video") {}
                .accessibilityIdentifier("video.native")
                .nitpickElement("video.native_button")
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .nitpickScreen("Video")
        .task {
            let url = await VideoMaker.makeIfNeeded()
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            p.isMuted = true
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}

struct PerfScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            DiagText().padding(8)
            List(0..<200, id: \.self) { index in
                HStack {
                    Text("Row \(index)")
                    Spacer()
                    Text("tap me").foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("row.\(index)")
                .nitpickElement("row.\(index)")
            }
            .accessibilityIdentifier("perf.list")
        }
        .navigationTitle("200 rows")
        .navigationBarTitleDisplayMode(.inline)
        .nitpickScreen("Perf list")
    }
}

/// The hard case: a plain scroll view where all 200 elements exist at the same time.
struct PerfEagerScreen: View {
    var body: some View {
        VStack(spacing: 0) {
            DiagText().padding(8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<200, id: \.self) { index in
                        HStack {
                            Text("Row \(index)")
                            Spacer()
                            Text("tap me").foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .frame(height: 48)
                        .accessibilityIdentifier("row.\(index)")
                        .nitpickElement("row.\(index)")
                    }
                }
            }
            .accessibilityIdentifier("perf.list")
        }
        .navigationTitle("200 rows eager")
        .navigationBarTitleDisplayMode(.inline)
        .nitpickScreen("Perf eager")
    }
}
