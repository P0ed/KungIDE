import SwiftUI
import ProgramCompiler

struct ProgramView: View {
	@Environment(\.colorScheme) var colorScheme

	@State var program: String = UserDefaults.standard.savedProgram
	@State var attributes: Attributes?
	@State var output: String = ""
	@State var input: String = ""

	@State var running = false
	@State var editorHidden = false
	@State var consoleHidden = true
	@State var debug = UserDefaults.standard.debugEnabled {
		didSet { UserDefaults.standard.debugEnabled = debug }
	}

	@State var scope: Scope?
	@State var executable: Program?

	@State var programChange: TimeInterval = .zero
	@State var outputChange: TimeInterval = .zero

    var body: some View {
		VStack(spacing: 0) {
			toolBar
			GeometryReader { ctx in
				let full = editorHidden || consoleHidden
				let height = ctx.size.height * (full ? 1 : 0.5)
				let offset = ctx.size.height * (full ? 0.5 : 0.75)
				if !editorHidden {
					TextEditor(text: $program, attributes: $attributes)
						.frame(height: height)
						.clipped()
				}
				if !consoleHidden {
					console
						.position(x: ctx.size.width / 2, y: offset)
						.frame(width: ctx.size.width, height: height)
				}
			}
		}
		.onAppear {
			attributes = try? program.highlighted(tokens: program.tokenized())
		}
		.onChange(of: program) { _, _ in
			DispatchQueue.parsing.async { [program] in
				let attrs = try? program.highlighted(tokens: program.tokenized())
				DispatchQueue.main.async {
					attributes = attrs
				}
			}
		}
		.background(colorScheme.editorColor)
    }

	var toolBar: some View {
		HStack(spacing: 12) {
			button("s") { UserDefaults.standard.savedProgram = program }
			button("b") { build() }
			button("r") { run() }
			button(".") { stop() }
			Spacer()
			button("p") {
				NSPasteboard.general.declareTypes([.string], owner: nil)
				NSPasteboard.general.setString(output, forType: .string)
			}
			button("k") { output = "" }
			button("e", !editorHidden) { editorHidden.toggle(); consoleHidden = editorHidden ? false : consoleHidden }
			button("t", !consoleHidden) { consoleHidden.toggle(); editorHidden = consoleHidden ? false : editorHidden }
			button("d", debug, { debug.toggle() })
		}
		.padding(.init(top: 8, leading: 12, bottom: 8, trailing: 12))
		.frame(height: 36, alignment: .top)
		.background(colorScheme.consoleColor)
	}

	func button(_ key: Character, _ active: Bool = false, _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(.init("⌘ + \(String(key).uppercased())"))
				.font(.code)
				.padding(.horizontal, 4)
		}
		.buttonStyle(.accessoryBarAction)
		.keyboardShortcut(.init(key), modifiers: .command)
		.background(active ? colorScheme.tintColor : .clear)
		.background(in: .rect(cornerRadius: 6))
	}

	var console: some View {
		ScrollView {
			ScrollViewReader { proxy in
				Text(output)
					.id("out")
					.font(.code)
					.lineSpacing(4)
					.onChange(of: output) { _, _ in
						let time = CACurrentMediaTime()
						let scroll = { proxy.scrollTo("out", anchor: .bottom) }
						if time - outputChange > 0.1 {
							withAnimation { scroll() }
						} else {
							scroll()
						}
						outputChange = time
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(4)
			}
		}
		.background(colorScheme.consoleColor)
		.contentMargins(.bottom, 24, for: .scrollContent)
		.overlay { commandLineInput }
	}

	var commandLineInput: some View {
		VStack {
			Spacer()
			ZStack {
				colorScheme.overlayColor
					.frame(maxWidth: .infinity, maxHeight: 24, alignment: .bottom)

				TextField("", text: $input)
					.onSubmit { print("\n\(input)"); input = "" }
					.textFieldStyle(.plain)
					.font(.code)
					.padding(.horizontal, 12)
					.frame(maxWidth: .infinity, maxHeight: 24)
			}
		}
	}

	func build() {
		do {
			output = ""
			scope = nil
			executable = nil
			let scp = try Scope(program: program)
			scope = scp
			let program = try scp.compile()
			executable = program

			print("\(scp)\n\nprogram:\n\t\(program.description.aligned)\n")
		} catch {
			var scp = ""
			if let scope { scp = "\(scope)\n" }
			print("\(scp)error:\n\t\(error)\n")
		}
	}

	func run() {
		guard !running else { return stop() }
		build()
		guard let executable, let scope else { return }
		running = true

		DispatchQueue.running.async {
			_ = executable.run(
				scope: scope,
				breakpoint: { pc, inn in
					var halt = 0 as Int32
					var throttle = false
					DispatchQueue.main.sync {
						halt = running ? 0 : 1
						throttle = debug
						if debug { print("\t\(inn.description(at: Int(pc)))\n") }
					}
					if throttle { usleep(1 << 16) }
					return halt
				},
				print: { x in DispatchQueue.main.async { print(x) } }
			)
			DispatchQueue.main.async { running = false }
		}
	}

	func stop() {
		running = false
	}

	func print(_ str: String) {
		consoleHidden = false

		output += str
		if output.count > 1 << 12 {
			let s = output.split(separator: "\n", omittingEmptySubsequences: false)
			output = "\n" + s.dropFirst(s.count / 2).joined(separator: "\n")
		}
	}
}
