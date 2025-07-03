# Troubleshooting Guide für Claude-Gemini Bridge

## 🔧 Häufige Probleme und Lösungen

### Installation & Setup

#### Hook wird nicht ausgeführt
**Symptom:** Claude verhält sich normal, aber Gemini wird nie aufgerufen

**Lösungsschritte:**
1. Prüfe Claude Settings:
   ```bash
   cat ~/.claude/settings.json
   ```
   
2. Teste Hook manuell:
   ```bash
   echo '{"tool_name":"Read","tool_input":{"file_path":"test.txt"},"session_id":"test"}' | ./hooks/gemini-bridge.sh
   ```

3. Prüfe Berechtigungen:
   ```bash
   ls -la hooks/gemini-bridge.sh
   # Sollte ausführbar sein (x-Flag)
   ```

4. Prüfe Hook-Konfiguration:
   ```bash
   jq '.hooks' ~/.claude/settings.json
   ```

**Lösung:** Re-Installation ausführen:
```bash
./install.sh
```

---

#### "command not found: jq"
**Symptom:** Fehler beim Ausführen von Scripts

**Lösung:**
- **macOS:** `brew install jq`
- **Linux:** `sudo apt-get install jq`
- **Alternative:** Nutze den Installer, der jq-Abhängigkeiten prüft

---

#### "command not found: gemini"
**Symptom:** Bridge kann Gemini nicht finden

**Lösungsschritte:**
1. Prüfe Gemini Installation:
   ```bash
   which gemini
   gemini --version
   ```

2. Teste Gemini manuell:
   ```bash
   echo "Test" | gemini -p "Say hello"
   ```

3. Prüfe PATH:
   ```bash
   echo $PATH
   ```

**Lösung:** Installiere Gemini CLI oder füge zu PATH hinzu

---

### Gemini-Integration

#### Gemini antwortet nicht
**Symptom:** Hook läuft, aber Gemini gibt keine Antwort zurück

**Debug-Schritte:**
1. Aktiviere verbose Logging:
   ```bash
   # In ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf
   DEBUG_LEVEL=3
   ```

2. Prüfe Gemini-Logs:
   ```bash
   tail -f ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log | grep -i gemini
   ```

3. Teste Gemini API-Key:
   ```bash
   gemini "test" -p "Hello"
   ```

**Häufige Ursachen:**
- Fehlender oder ungültiger API-Key
- Rate-Limiting erreicht
- Netzwerkprobleme
- Gemini-Service nicht verfügbar

---

#### "Rate limiting: sleeping Xs"
**Symptom:** Bridge wartet zwischen Aufrufen

**Erklärung:** Normal! Verhindert API-Überlastung.

**Anpassen:**
```bash
# In debug.conf
GEMINI_RATE_LIMIT=0.5  # Reduziere auf 0.5 Sekunden
```

---

#### Cache-Probleme
**Symptom:** Veraltete Antworten von Gemini

**Lösung:**
```bash
# Cache komplett leeren
rm -rf ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/cache/gemini/*

# Oder Cache-TTL reduzieren (in debug.conf)
GEMINI_CACHE_TTL=1800  # 30 Minuten statt 1 Stunde
```

---

### Pfad-Konvertierung

#### @ Pfade werden nicht konvertiert
**Symptom:** Gemini kann Dateien nicht finden

**Debug:**
1. Teste Pfad-Konvertierung isoliert:
   ```bash
   cd ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/lib
   source path-converter.sh
   convert_claude_paths "@src/main.py" "/Users/tim/project"
   ```

2. Prüfe Working Directory in Logs:
   ```bash
   grep "Working directory" ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log
   ```

**Häufige Ursachen:**
- Fehlendes working_directory im Tool-Call
- Relative Pfade ohne @ Prefix
- Falsche Verzeichnisstrukturen

---

### Performance & Verhalten

#### Gemini wird zu oft aufgerufen
**Symptom:** Jeder kleine Read-Befehl geht an Gemini

**Anpassungen in debug.conf:**
```bash
MIN_FILES_FOR_GEMINI=5        # Erhöhe Mindest-Dateianzahl
MIN_FILE_SIZE_FOR_GEMINI=50240  # Erhöhe Mindest-Dateigröße
```

---

#### Gemini wird nie aufgerufen
**Symptom:** Auch große Analysen gehen nicht an Gemini

**Debug:**
1. Aktiviere DRY_RUN Modus:
   ```bash
   # In debug.conf
   DRY_RUN=true
   ```

2. Prüfe Entscheidungslogik:
   ```bash
   grep "should_delegate_to_gemini" ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log
   ```

**Anpassungen:**
```bash
MIN_FILES_FOR_GEMINI=1        # Reduziere Schwellwerte
MIN_FILE_SIZE_FOR_GEMINI=1024 # 1KB
```

---

## 🔍 Debug-Workflow

### 1. Problem reproduzieren
```bash
# Aktiviere Input-Capturing
# In debug.conf: CAPTURE_INPUTS=true

# Führe problematischen Claude-Befehl aus
# Input wird automatisch gespeichert
```

### 2. Logs analysieren
```bash
# Aktuelle Debug-Logs
tail -f ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log

# Error-Logs
tail -f ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/errors.log

# Alle Logs des Tages
less ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/$(date +%Y%m%d).log
```

### 3. Isoliert testen
```bash
# Interaktive Tests
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/test/manual-test.sh

# Automatisierte Tests
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/test/test-runner.sh

# Replay gespeicherter Inputs
ls ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/debug/captured/
cat ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/debug/captured/FILENAME.json | ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/gemini-bridge.sh
```

### 4. Schritt-für-Schritt Debugging
```bash
# Höchstes Debug-Level
# In debug.conf: DEBUG_LEVEL=3

# Dry-Run Modus (kein echter Gemini-Aufruf)
# In debug.conf: DRY_RUN=true

# Einzelne Library-Funktionen testen
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/lib/path-converter.sh
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/lib/json-parser.sh
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/lib/gemini-wrapper.sh
```

---

## ⚙️ Konfiguration

### Debug-Level
```bash
# In ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf

DEBUG_LEVEL=0  # Kein Debug-Output
DEBUG_LEVEL=1  # Basis-Informationen (Standard)
DEBUG_LEVEL=2  # Detaillierte Informationen
DEBUG_LEVEL=3  # Vollständiges Tracing
```

### Gemini-Einstellungen
```bash
GEMINI_CACHE_TTL=3600      # Cache-Zeit in Sekunden
GEMINI_TIMEOUT=30          # Timeout pro Aufruf
GEMINI_RATE_LIMIT=1        # Sekunden zwischen Aufrufen
GEMINI_MAX_FILES=20        # Max Dateien pro Aufruf
```

### Entscheidungskriterien
```bash
MIN_FILES_FOR_GEMINI=3           # Mindest-Dateianzahl
MIN_FILE_SIZE_FOR_GEMINI=10240   # Mindest-Gesamtgröße (10KB)
MAX_TOTAL_SIZE_FOR_GEMINI=10485760  # Max-Gesamtgröße (10MB)

# Ausgeschlossene Dateien
GEMINI_EXCLUDE_PATTERNS="*.secret|*.key|*.env|*.password"
```

---

## 🧹 Wartung

### Cache bereinigen
```bash
# Manuell
rm -rf ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/cache/gemini/*

# Automatisch (über debug.conf)
AUTO_CLEANUP_CACHE=true
CACHE_MAX_AGE_HOURS=24
```

### Logs bereinigen
```bash
# Manuell
rm -rf ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/*

# Automatisch (über debug.conf)
AUTO_CLEANUP_LOGS=true
LOG_MAX_AGE_DAYS=7
```

### Captured Inputs bereinigen
```bash
rm -rf ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/debug/captured/*
```

---

## 🆘 Notfall-Deaktivierung

### Hook temporär deaktivieren
```bash
# Backup der Settings
cp ~/.claude/settings.local.json ~/.claude/settings.local.json.backup

# Hook entfernen
jq 'del(.hooks)' ~/.claude/settings.local.json > /tmp/claude_settings
mv /tmp/claude_settings ~/.claude/settings.local.json
```

### Hook wieder aktivieren
```bash
# Settings wiederherstellen
cp ~/.claude/settings.local.json.backup ~/.claude/settings.local.json

# Oder neu installieren
${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/install.sh
```

### Komplett deinstallieren
```bash
# Hook entfernen
jq 'del(.hooks)' ~/.claude/settings.local.json > /tmp/claude_settings
mv /tmp/claude_settings ~/.claude/settings.local.json

# Bridge entfernen
rm -rf ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}
```

---

## 📞 Support & Reporting

### Log-Sammlung für Support
```bash
# Erstelle Debug-Paket
tar -czf claude-gemini-debug-$(date +%Y%m%d).tar.gz \
  ~/.claude/settings.local.json \
  ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/logs/debug/ \
  ${CLAUDE_GEMINI_BRIDGE_DIR:-~/.claude-gemini-bridge}/hooks/config/debug.conf
```

### Hilfreiche Informationen
- Claude Version: `claude --version`
- Gemini Version: `gemini --version`
- Betriebssystem: `uname -a`
- Shell: `echo $SHELL`
- PATH: `echo $PATH`

### Häufige Fehlermeldungen
- **"Invalid JSON received"**: Input-Validation fehlgeschlagen
- **"Gemini initialization failed"**: Gemini CLI nicht verfügbar
- **"Files too large/small"**: Schwellwerte nicht erfüllt
- **"Rate limiting"**: Normal, zeigt korrekte Funktion
- **"Cache expired"**: Normal, Cache wird erneuert