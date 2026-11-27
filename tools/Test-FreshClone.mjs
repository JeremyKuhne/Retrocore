// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// A repository that develops with Retrocore builds from a fresh clone with nothing but the .NET SDK and the pinned
// tool: `dotnet tool restore`, then `dotnet retrocore build --all`. Two repositories are checked, each committed to Git
// and cloned before it builds: one `retrocore new` makes, and the adventure sample as it would stand in its own
// repository (the files Git tracks or would, not those it ignores). The tool comes from a local pack, as it is
// published nowhere yet: a nuget.config above the clones maps retrocore to that folder alone, and every other package,
// such as the runtime packs `dotnet run` restores for the sample's C# step, to nuget.org. The run has a NuGet packages
// folder and a .NET CLI home of its own, so no copy restored before stands in for the one packed here. Each target must
// write its files, and the build must leave the clone's working tree clean, its output ignored.
//
//   node tools/Test-FreshClone.mjs                  # packs the tool from the Release build first
//   node tools/Test-FreshClone.mjs --feed <folder>  # a folder that holds retrocore's package already

import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import assert from "node:assert/strict";

const root = resolve(import.meta.dirname, "..");
const work = mkdtempSync(join(tmpdir(), "retrocore-clone-"));
// The NuGet packages folder and the .NET CLI's home (where its cache of restored local tools is) are the run's own, so
// no tool restored before stands in for the one packed here.
const environment = {
    ...process.env,
    NUGET_PACKAGES: join(work, "packages"),
    DOTNET_CLI_HOME: join(work, "home"),
    // No MSBuild server, worker node or compiler server outlives a build to hold the run's files open, so its folder
    // can be removed afterwards; the removal still retries, for anything else that has a file open a moment longer.
    DOTNET_CLI_USE_MSBUILD_SERVER: "0",
    MSBUILDDISABLENODEREUSE: "1",
    UseSharedCompilation: "false",
    DOTNET_NOLOGO: "true",
    DOTNET_CLI_TELEMETRY_OPTOUT: "true"
};

function run(command, args, cwd) {
    const result = spawnSync(command, args, { cwd, env: environment, encoding: "utf8" });
    const shown = `${command} ${args.join(" ")} (in ${cwd})`;
    assert.equal(result.error, undefined, `${shown}: ${result.error}`);
    assert.equal(result.status, 0, `${shown} failed:\n${result.stdout}${result.stderr}`);
    return result.stdout;
}

const git = (cwd, ...args) => run("git", [
    "-c", "user.name=Retrocore", "-c", "user.email=retrocore@example.invalid", "-c", "core.autocrlf=false",
    "-c", "commit.gpgsign=false", ...args
], cwd);

// Commits a folder as a repository of its own, then clones it, as a fresh clone would be.
function cloned(origin, name) {
    git(origin, "init", "-q", "-b", "main");
    git(origin, "add", "-A");
    git(origin, "commit", "-q", "-m", "Start");
    const clone = join(work, "clones", name);
    mkdirSync(dirname(clone), { recursive: true });
    git(dirname(clone), "clone", "-q", origin, clone);
    return clone;
}

// Restores the pinned tool in a clone and builds every target, which each write their files.
function build(clone, name, check = () => {}) {
    run("dotnet", ["tool", "restore"], clone);
    const output = run("dotnet", ["retrocore", "build", "--all"], clone);
    const project = JSON.parse(readFileSync(join(clone, "retrocore.json"), "utf8").replace(/^\s*\/\/.*$/gm, ""));
    const targets = Object.keys(project.targets);
    for (const target of targets) {
        assert.match(output, new RegExp(`^${project.name}/${target}: `, "m"), `${name}: ${target} built`);
        const folder = join(clone, "artifacts", target);
        assert.ok(existsSync(folder) && readdirSync(folder).length > 0, `${name}: ${target} wrote its files to artifacts/${target}/`);
    }

    check(clone);
    const status = git(clone, "status", "--porcelain", "--untracked-files=all");
    assert.equal(status, "", `${name}: the build leaves the clone's working tree clean:\n${status}`);
    console.log(`${name}: a fresh clone restored the tool and built ${targets.length} targets (${targets.join(", ")}).`);
}

try {
    // The tool's package, and a NuGet configuration above the clones that takes it from its folder alone.
    const feedArgument = process.argv.indexOf("--feed");
    let feed;
    if (feedArgument > 0) {
        assert.ok(process.argv[feedArgument + 1], "--feed names a folder");
        feed = resolve(process.argv[feedArgument + 1]);
    } else {
        feed = join(work, "feed");
        run("dotnet", ["pack", join(root, "src", "Retrocore.Debug", "Retrocore.Debug.csproj"), "-c", "Release", "--no-build", "-o", feed], root);
    }

    const packages = readdirSync(feed).filter(file => /^retrocore\..+\.nupkg$/.test(file));
    assert.equal(packages.length, 1, `${feed} holds one retrocore package: ${packages.join(", ")}`);
    const version = packages[0].slice("retrocore.".length, -".nupkg".length);
    writeFileSync(join(work, "nuget.config"), `<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="retrocore" value="${feed}" />
  </packageSources>
  <packageSourceMapping>
    <packageSource key="retrocore">
      <package pattern="retrocore" />
    </packageSource>
    <packageSource key="nuget.org">
      <package pattern="*" />
    </packageSource>
  </packageSourceMapping>
</configuration>
`);

    // retrocore new, run by the packed tool installed on its own, makes the first repository.
    const tool = join(work, "tool");
    run("dotnet", ["tool", "install", "retrocore", "--version", version, "--tool-path", tool], work);
    const retrocore = join(tool, process.platform === "win32" ? "retrocore.exe" : "retrocore");
    assert.equal(run(retrocore, ["--version"], work).trim(), version, "the tool's --version is its package's");
    const starter = join(work, "origin", "starter");
    run(retrocore, ["new", "6502", "starter", "--output", starter], work);
    const pinned = JSON.parse(readFileSync(join(starter, ".config", "dotnet-tools.json"), "utf8")).tools.retrocore.version;
    assert.equal(pinned, version, "retrocore new pins the tool's own version");
    build(cloned(starter, "starter"), "retrocore new's project");

    // The adventure sample, its files Git tracks or would track, as its own repository: the working tree as a commit
    // of it would be, so a tracked file deleted here is left out.
    const adventure = join(work, "origin", "adventure");
    const files = run("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "sample/adventure"], root).split("\0").filter(file => file && existsSync(join(root, file)));
    for (const file of files) {
        const target = join(adventure, file.slice("sample/adventure/".length));
        mkdirSync(dirname(target), { recursive: true });
        cpSync(join(root, file), target);
    }

    const sample = JSON.parse(readFileSync(join(adventure, ".config", "dotnet-tools.json"), "utf8")).tools.retrocore.version;
    assert.equal(sample, version, "the sample pins the version this repository builds");
    // Its step built the packer from the clone alone; the packer's reference engine plays Pirate Adventure's win, one of
    // the transcripts its workflow plays.
    build(cloned(adventure, "adventure"), "the adventure sample", clone => run("dotnet",
        ["run", "tools/packer.cs", "--", "play", "obj/pirate.bin", "games/pirate-win.in", "--echo", "--expect", "games/pirate-win.out"], clone));

    console.log(`Fresh clones passed on ${process.platform}: with retrocore ${version} from a local pack, both repositories restore the tool and build every target.`);
} finally {
    // Retried, for anything other than a build server that has a file open a moment longer.
    rmSync(work, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
}
