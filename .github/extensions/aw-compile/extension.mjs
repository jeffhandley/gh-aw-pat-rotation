// Extension: aw-compile
// Copilot CLI skill that wraps the aw-compile scripts for compiling
// agentic workflows with PAT pool rotation post-compile edits.
//
// Activates when the user asks to compile an agentic workflow.
// Detects the OS and shells out to the appropriate script
// (aw-compile.ps1 on Windows, aw-compile.sh on Linux/macOS).

import { execFile, exec } from "node:child_process";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import { joinSession } from "@github/copilot-sdk/extension";

function findRepoRoot(startDir, workflow) {
    // Check startDir itself
    try {
        const files = readdirSync(join(startDir, ".github", "workflows"));
        if (!workflow || files.includes(`${workflow}.md`)) return startDir;
    } catch { /* not here */ }

    // Check immediate children
    try {
        for (const entry of readdirSync(startDir, { withFileTypes: true })) {
            if (!entry.isDirectory()) continue;
            const candidate = join(startDir, entry.name);
            try {
                const files = readdirSync(join(candidate, ".github", "workflows"));
                if (!workflow || files.includes(`${workflow}.md`)) return candidate;
            } catch { /* not here */ }
        }
    } catch { /* can't read dir */ }

    return null;
}

const session = await joinSession({
    tools: [
        {
            name: "aw_compile",
            description:
                "Compiles agentic workflows using `gh aw compile` and applies post-compile " +
                "edits to use the select-copilot-pat action for PAT pool rotation. " +
                "Reads `metadata.copilot-pat-pool` from each workflow's frontmatter to " +
                "determine which COPILOT_<POOL>_N secrets to wire in. " +
                "Pass a workflow name to compile one, or omit to compile all.",
            parameters: {
                type: "object",
                properties: {
                    workflow: {
                        type: "string",
                        description: "Workflow name (without .md extension) to compile, or empty to compile all.",
                    },
                },
            },
            skipPermission: true,
            handler: async (args) => {
                const repoRoot = findRepoRoot(process.cwd(), args.workflow);
                if (!repoRoot) {
                    return {
                        textResultForLlm: "No repository with .github/workflows found in current directory or its subdirectories.",
                        resultType: "failure",
                    };
                }

                const isWindows = process.platform === "win32";
                const scriptPath = join(repoRoot, ".github", isWindows ? "aw-compile.ps1" : "aw-compile.sh");
                const scriptArgs = args.workflow ? [args.workflow] : [];

                let cmd, cmdArgs;
                if (isWindows) {
                    cmd = "pwsh";
                    cmdArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", scriptPath, ...scriptArgs];
                } else {
                    cmd = "bash";
                    cmdArgs = [scriptPath, ...scriptArgs];
                }

                return new Promise((resolve) => {
                    execFile(cmd, cmdArgs, { cwd: repoRoot, maxBuffer: 10 * 1024 * 1024 }, (err, stdout, stderr) => {
                        if (err) {
                            resolve({
                                textResultForLlm: `Compile failed:\n${stdout}\n${stderr}`.trim(),
                                resultType: "failure",
                            });
                        } else {
                            resolve(stdout.trim());
                        }
                    });
                });
            },
        },
    ],
});
