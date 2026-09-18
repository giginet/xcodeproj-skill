#!/usr/bin/env python3
"""Add, remove or list Swift package dependencies in a project.xcproj (Xcode 27.2+).

xcrun xcodeproj has no package commands, but the JSON project format keeps
packages in two plain places, so this script edits them directly:

  * project-level  "packages": [ { "kind": "remote", "repository": URL, "version": {...} }
                                 { "kind": "local",  "path": "../Foo" } ]
  * per-target     "package-product-members": [ { "package": <name>, "product-name": <product>,
                                                  "build-phase": { "build-phase": "frameworks" } } ]

The file is JSON5-flavoured (trailing commas), so it is parsed after stripping
trailing commas outside string literals and written back as plain JSON, which
Xcode and xcodeproj both accept; the next xcodeproj write re-canonicalizes it.

usage:
  xcproj-package.py list   <Project.xcodeproj>
  xcproj-package.py add    <Project.xcodeproj> --url <git-url> --requirement <req>
                           [--target <t> --product <name> [--product ...]] [--package-name <name>]
  xcproj-package.py add    <Project.xcodeproj> --path <relative-dir>
                           [--target <t> --product <name> [--product ...]] [--package-name <name>]
  xcproj-package.py remove <Project.xcodeproj> (--url <git-url> | --path <dir> | --package-name <name>)

<req> forms: 1.2.3 | from:1.2.3 | upToNextMajor:1.2.3 | upToNextMinor:1.2.3 |
             exact:1.2.3 | range:1.0.0..<2.0.0 | branch:main | revision:<sha>
Exit codes: 0 ok, 1 not found / conflict, 2 bad input.
"""
import argparse
import json
import os
import re
import sys


def strip_trailing_commas(text):
    out = []
    in_str = False
    esc = False
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            out.append(c)
        elif c == ",":
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                pass  # drop the trailing comma
            else:
                out.append(c)
        else:
            out.append(c)
        i += 1
    return "".join(out)


def load(project_path):
    xcproj = os.path.join(project_path, "project.xcproj")
    if not os.path.isfile(xcproj):
        sys.exit(f"error: {xcproj} not found (pbxproj projects are not supported; "
                 "add the package in Xcode or convert the project to project.xcproj)")
    with open(xcproj, encoding="utf-8") as f:
        raw = f.read()
    try:
        return xcproj, json.loads(strip_trailing_commas(raw))
    except json.JSONDecodeError as e:
        sys.exit(f"error: could not parse {xcproj}: {e}")


def save(xcproj, doc):
    with open(xcproj, "w", encoding="utf-8") as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write("\n")


def package_name(pkg):
    if pkg.get("kind") == "remote":
        return re.sub(r"\.git$", "", pkg["repository"].rstrip("/").rsplit("/", 1)[-1])
    return os.path.basename(os.path.normpath(pkg["path"]))


def parse_requirement(req):
    if ":" not in req:
        return {"up-to-next-major-version": req}
    kind, _, value = req.partition(":")
    kind = kind.strip().lower()
    value = value.strip()
    if kind in ("from", "uptonextmajor", "up-to-next-major"):
        return {"up-to-next-major-version": value}
    if kind in ("uptonextminor", "up-to-next-minor"):
        return {"up-to-next-minor-version": value}
    if kind in ("exact", "version"):
        return {"version": value}
    if kind == "branch":
        return {"branch": value}
    if kind == "revision":
        return {"revision": value}
    if kind == "range":
        if "..<" not in value:
            sys.exit("error: range requirement must look like range:1.0.0..<2.0.0")
        return {"version-range": value}
    sys.exit(f"error: unknown requirement '{req}'")


def describe_version(v):
    if not v:
        return "(no version constraint)"
    (k, val), = v.items()
    return f"{k} {val}"


def cmd_list(args):
    _, doc = load(args.project)
    packages = doc.get("packages", [])
    if not packages:
        print("No Swift packages.")
        return
    for pkg in packages:
        name = package_name(pkg)
        if pkg.get("kind") == "remote":
            print(f"📦 {name}  {pkg['repository']}  {describe_version(pkg.get('version'))}")
        else:
            print(f"📁 {name}  {pkg['path']}")
        for target in doc.get("targets", []):
            for m in target.get("package-product-members", []):
                if m.get("package") == name:
                    phase = m.get("build-phase", {}).get("build-phase", "?")
                    print(f"    -> {target['name']}: {m['product-name']} ({phase})")


def cmd_add(args):
    if bool(args.url) == bool(args.path):
        sys.exit("error: give exactly one of --url or --path")
    if args.product and not args.target:
        sys.exit("error: --product requires --target")
    xcproj, doc = load(args.project)
    packages = doc.setdefault("packages", [])
    if args.url:
        if not args.requirement:
            sys.exit("error: --requirement is required with --url")
        pkg = {"kind": "remote", "repository": args.url, "version": parse_requirement(args.requirement)}
        exists = any(p.get("kind") == "remote" and p.get("repository") == args.url for p in packages)
    else:
        pkg = {"kind": "local", "path": args.path}
        exists = any(p.get("kind") == "local" and p.get("path") == args.path for p in packages)
    name = args.package_name or package_name(pkg)
    if not exists:
        packages.append(pkg)
    if args.target:
        targets = [t for t in doc.get("targets", []) if t.get("name") == args.target]
        if not targets:
            sys.exit(f"error: no target named '{args.target}'")
        target = targets[0]
        phases = target.get("build-phases", [])
        if not any(p == "frameworks" or (isinstance(p, dict) and p.get("kind") == "frameworks") for p in phases):
            sys.exit(f"error: target '{args.target}' has no frameworks phase; "
                     "run: xcrun xcodeproj target phase add --target <t> frameworks")
        members = target.setdefault("package-product-members", [])
        for product in args.product or [name]:
            if any(m.get("package") == name and m.get("product-name") == product for m in members):
                continue
            members.append({"package": name, "product-name": product,
                            "build-phase": {"build-phase": "frameworks"}})
    save(xcproj, doc)
    print(f"{'Linked' if exists else 'Added'} package '{name}'"
          + (f" to target '{args.target}' (products: {', '.join(args.product or [name])})" if args.target else ""))


def cmd_remove(args):
    if sum(bool(x) for x in (args.url, args.path, args.package_name)) != 1:
        sys.exit("error: give exactly one of --url, --path or --package-name")
    xcproj, doc = load(args.project)
    packages = doc.get("packages", [])
    keep, removed = [], []
    for p in packages:
        match = (args.url and p.get("kind") == "remote" and p.get("repository") == args.url) or \
                (args.path and p.get("kind") == "local" and p.get("path") == args.path) or \
                (args.package_name and package_name(p) == args.package_name)
        (removed if match else keep).append(p)
    if not removed:
        sys.exit("error: no matching package")
    names = {package_name(p) for p in removed}
    doc["packages"] = keep
    if not keep:
        del doc["packages"]
    unlinked = 0
    for target in doc.get("targets", []):
        members = target.get("package-product-members")
        if not members:
            continue
        kept = [m for m in members if m.get("package") not in names]
        unlinked += len(members) - len(kept)
        if kept:
            target["package-product-members"] = kept
        else:
            del target["package-product-members"]
    save(xcproj, doc)
    print(f"Removed package(s) {', '.join(sorted(names))}; unlinked {unlinked} product member(s).")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("list"); p.add_argument("project"); p.set_defaults(func=cmd_list)
    p = sub.add_parser("add"); p.add_argument("project")
    p.add_argument("--url"); p.add_argument("--path"); p.add_argument("--requirement")
    p.add_argument("--target"); p.add_argument("--product", action="append"); p.add_argument("--package-name")
    p.set_defaults(func=cmd_add)
    p = sub.add_parser("remove"); p.add_argument("project")
    p.add_argument("--url"); p.add_argument("--path"); p.add_argument("--package-name")
    p.set_defaults(func=cmd_remove)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
