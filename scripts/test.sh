#!/bin/zsh
# Runs the unit tests. With only the Command Line Tools installed, SwiftPM does not find
# Swift Testing on its own, so point it at the framework folder when that folder exists.
set -e
cd "$(dirname "$0")/.."
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [[ -d "$F/Testing.framework" ]] && ! xcode-select -p | grep -q Xcode.app; then
  exec swift test -Xswiftc -F$F -Xlinker -F$F -Xlinker -rpath -Xlinker $F -Xlinker -rpath -Xlinker $L "$@"
fi
exec swift test "$@"
