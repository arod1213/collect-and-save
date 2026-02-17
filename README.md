# CollectAndSave CLI Tool

The `CollectAndSave` utility allows you to work with Ableton session files (`.als`) to inspect, check, and collect files used in your sessions.  

---

## Usage

```bash
cns <command> <filepaths...>
```

- **pos 1:** Command — one of `xml`, `check`, or `save`  
- **pos 2+:** One or more `.als` filepaths to be processed  

---

## Commands

### 1. XML

Writes out a gzipped Ableton document into a readable XML format.  
The output is sent to `stdout` and can be redirected to a file.

**Example:**

```bash
cns xml './myset.als' > data.xml
```

---

### 2. CHECK

Performs a dry-run of collecting and saving files.  
Shows which files would be collected and which files are missing.  

**Example:**

```bash
cns check './myset.als'
```

---

### 3. SAVE

Collects and saves the specified session files.  
Files are collected into the **parent directory** where the Ableton file is located.

**Example:**

```bash
cns save './myset.als'
```

---

## Multiple Filepaths

You can specify multiple `.als` files in a single command.  
All arguments after the first position will be parsed.

**Example:**

```bash
cns save './set1.als' './set2.als'
```

---

## Notes

- Always ensure that your `.als` filepaths are correct and accessible from your current working directory.  
- `check` mode is safe and does not modify any files — ideal for dry-runs.  
- `save` mode performs the actual collection of files into the session directory.  
