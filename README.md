# CollectAndSave CLI Tool

The `CollectAndSave` utility allows you to work with Ableton session files (`.als`) to inspect, check, and collect files used in your sessions.  
Supports Live 9 - Live 12 sets

---

## Usage

```bash
collect_and_save <command> <filepath>
```

- **pos 1:** Command — one of `xml`, `check`, or `save`  
- **pos 2:** Filepath (either .als file or directory)

---

## Commands

### 1. XML

Writes out a gzipped Ableton document into a readable XML format.  
The output is sent to `stdout` and can be redirected to a file.

**Example:**

```bash
collect_and_save xml './myset.als' > data.xml
```

---

### 2. CHECK

Performs a dry-run of collecting and saving files.  
Shows which files would be collected and which files are missing.  

**Example:**

```bash
collect_and_save check './myset.als'
```

---

### 3. SAVE

Collects and saves the specified session files.  
Files are collected into the **parent directory** where the Ableton file is located.

**Example:**

```bash
collect_and_save save './myset.als'
```

---

### 4. SAFE

Prompts file by file if the user wants to collect the missing file

**Example:**

```bash
collect_and_save safe './myset.als'
```

---

## Multiple Filepaths

You can save multiple sets by providing a directory instead of a file

**Example:**

```bash
collect_and_save save './my ableton project'
```

---

## Notes

- Always ensure that your `.als` filepaths are correct and accessible from your current working directory.  
- `check` mode is safe and does not modify any files — ideal for dry-runs.  
- `save` mode performs the actual collection of files into the session directory.  
