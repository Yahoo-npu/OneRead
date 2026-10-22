#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
SDK="${ONEREAD_SDK:-$(xcrun --show-sdk-path)}"
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then SDK="${ONEREAD_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"; fi
swiftc -sdk "$SDK" -swift-version 5 -module-cache-path "$PWD/.build/module-cache" Sources/OneRead/DataLocation.swift Sources/OneRead/DailyQuote.swift Sources/OneRead/ShelfOrganization.swift Sources/OneRead/EconomistRepository.swift Sources/OneRead/EconomistLibrary.swift Sources/OneRead/ForeignMagazines.swift Sources/OneRead/ExamVocabulary.swift Sources/OneRead/Vocabulary.swift Sources/OneRead/StoreTOC.swift Sources/OneRead/TableOfContents.swift Sources/OneRead/SettingsOperation.swift Sources/OneRead/CredentialDraft.swift Sources/OneRead/APIProfiles.swift Sources/OneRead/AgentDetection.swift Sources/OneRead/SentenceAnalysis.swift Sources/OneRead/Dictionary.swift Sources/OneRead/Models.swift Sources/OneRead/Assets.swift Sources/OneRead/TranslationPlan.swift Sources/OneRead/Store.swift Sources/OneRead/Importer.swift Sources/OneRead/Services.swift Tests/Smoke.swift -o .build/smoke-tests
.build/smoke-tests

# Catch reader script syntax regressions independently of Swift compilation.
if command -v node >/dev/null 2>&1; then
    python3 - <<'PYREADER'
from pathlib import Path
s = Path('Sources/OneRead/Reader.html').read_text()
Path('.build/reader-check.js').write_text(s.split('<script>')[1].split('</script>')[0])
PYREADER
    node --check .build/reader-check.js
    node --check Sources/OneRead/ReaderScroll.js
    node Tests/ReaderScroll.js
    node Tests/SentenceAnalysis.js
fi
