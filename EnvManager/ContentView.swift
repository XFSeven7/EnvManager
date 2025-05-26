import SwiftUI
import AppKit

struct EnvVar: Identifiable, Hashable {
    let id = UUID()
    var value: String // Only the directory path now
}

struct ContentView: View {
    @State private var envVars: [EnvVar] = []
    @State private var showAddSheet = false
    @State private var newValue = ""
    @State private var errorMessage = ""
    @State private var showDeleteAlert = false
    @State private var pendingDeleteIndex: Int?

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("User Environment Paths")
                    .font(.title2)
                Spacer()
                Button("Open .zshrc File") {
                    openZshrcFile()
                }
                Button("Add Path") {
                    newValue = ""
                    errorMessage = ""
                    showAddSheet = true
                }
            }

            List {
                ForEach(envVars.indices, id: \.self) { index in
                    HStack {
                        TextField("Directory path", text: $envVars[index].value)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit { saveImmediately() }

                        Spacer()

                        Button(action: {
                            pendingDeleteIndex = index
                            showDeleteAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Spacer()
                Button("Reload Environment in Terminal (source ~/.zshrc)") {
                    openTerminalWithSourceCommand()
                }
            }
            .padding(.top, 10)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            envVars = loadUserEnvVars()
        }
        .sheet(isPresented: $showAddSheet) {
            VStack {
                Text("Add Path")
                    .font(.headline)
                    .padding()

                TextField("Directory path (e.g., /opt/homebrew/bin)", text: $newValue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .padding()
                }

                HStack {
                    Button("Cancel") {
                        showAddSheet = false
                    }
                    Spacer()
                    Button("Add") {
                        if newValue.isEmpty {
                            errorMessage = "Path is required"
                            return
                        }
                        envVars.append(EnvVar(value: newValue))
                        saveImmediately()
                        showAddSheet = false
                    }
                }
                .padding()
            }
            .padding()
            .frame(width: 400, height: 200)
        }
        .alert("Delete Path?", isPresented: $showDeleteAlert, presenting: pendingDeleteIndex) { index in
            Button("Delete", role: .destructive) {
                envVars.remove(at: index)
                saveImmediately()
            }
            Button("Cancel", role: .cancel) { }
        } message: { index in
            Text("Are you sure you want to delete \"\(envVars[index].value)\"?")
        }
    }

    func saveImmediately() {
        saveToZshrc()
        silentlySourceZshrc()
        envVars = loadUserEnvVars()
    }

    func loadUserEnvVars() -> [EnvVar] {
        let home = URL(fileURLWithPath: "/Users/\(NSUserName())")
        let zshrcPath = home.appendingPathComponent(".zshrc").path

        guard let content = try? String(contentsOfFile: zshrcPath) else {
            print("[ERROR] Failed to read .zshrc")
            return []
        }

        let lines = content.components(separatedBy: .newlines)
        var result: [EnvVar] = []
        for line in lines {
            if line.contains("export PATH=\"$PATH:") {
                if let pathPart = line.components(separatedBy: "$PATH:").last?.replacingOccurrences(of: "\"", with: "") {
                    result.append(EnvVar(value: pathPart))
                }
            }
        }
        return result
    }

    func saveToZshrc() {
        let home = URL(fileURLWithPath: "/Users/\(NSUserName())")
        let zshrcPath = home.appendingPathComponent(".zshrc")
        let backupPath = home.appendingPathComponent(".zshrc.bak")
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: zshrcPath.path) {
            let initialContent = """
            # Created by EnvManager
            export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

            # ==== EnvManager Variables Start ====
            # ==== EnvManager Variables End ====
            """
            try? initialContent.write(to: zshrcPath, atomically: true, encoding: .utf8)
        }

        try? fileManager.copyItem(at: zshrcPath, to: backupPath)

        let original = (try? String(contentsOf: zshrcPath)) ?? ""

        var managedContent = "# ==== EnvManager Variables Start ===="
        for item in envVars {
            managedContent += "\nexport PATH=\"$PATH:\(item.value)\""
        }
        managedContent += "\n# ==== EnvManager Variables End ===="

        var newContent = ""
        if original.contains("# ==== EnvManager Variables Start ====") {
            newContent = original.replacingOccurrences(
                of: #"(?s)# ==== EnvManager Variables Start ====.*?# ==== EnvManager Variables End ===="#,
                with: managedContent,
                options: .regularExpression
            )
        } else {
            newContent = original + "\n\n" + managedContent
        }

        do {
            try newContent.write(to: zshrcPath, atomically: true, encoding: .utf8)
            print("[✅] .zshrc saved and backed up")
        } catch {
            print("[❌] Write error: \(error)")
        }
    }

    func silentlySourceZshrc() {
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", "source ~/.zshrc"]
        try? task.run()
    }

    func openZshrcFile() {
        let home = URL(fileURLWithPath: "/Users/\(NSUserName())")
        let zshrcPath = home.appendingPathComponent(".zshrc")
        NSWorkspace.shared.open(zshrcPath)
    }

    func openTerminalWithSourceCommand() {
        let command = """
        tell application \"Terminal\"
            activate
            do script \"source ~/.zshrc"
        end tell
        """

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", command]
        try? process.run()
    }
}
