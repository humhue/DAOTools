# translation_engine.nim

proc newTranslationIndex*(): TranslationIndex =
  TranslationIndex(
    byId: newTable[uint32, string](),
    byFile: newTable[string, TableRef[uint32, string]]()
  )

proc newDiscoveryIndex*(): DiscoveryIndex =
  newTable[string, TableRef[uint32, TlkEntry]]()

proc normalizeResourceKey*(key: string): string =
  key.replace('\\', '/').toLowerAscii()

proc makeResourceKey*(containerPath, filename: string): string =
  let container = containerPath.replace('\\', '/')
  if container == "" or container == "None" or container == "standalone":
    return filename.replace('\\', '/')
  container & " -> " & filename.replace('\\', '/')

proc recordDiscovered*(discovered: DiscoveryIndex, resourceKey: string,
                       id: uint32, line, nodePath: string) =
  let key = resourceKey.normalizeResourceKey()
  if not discovered.hasKey(key):
    discovered[key] = newTable[uint32, TlkEntry]()

  # Keep the first occurrence within one resource. If a malformed resource
  # reuses an ID for different text, the file-scoped JSON entry remains stable
  # instead of depending on traversal order.
  if not discovered[key].hasKey(id):
    discovered[key][id] = TlkEntry(line: line, node_path: nodePath)

proc discoveredLen*(discovered: DiscoveryIndex): int =
  for entries in discovered.values:
    result += entries.len

proc lineFromJson(node: JsonNode, context: string): string =
  case node.kind
  of JString:
    result = node.getStr()
  of JObject:
    if not node.hasKey("line") or node["line"].kind != JString:
      raise newException(ValueError, context & " must contain a string 'line' value")
    result = node["line"].getStr()
  else:
    raise newException(ValueError, context & " must be a string or an object with a 'line' value")

proc parseIdMap(node: JsonNode, target: TableRef[uint32, string], context: string) =
  if node.kind != JObject:
    raise newException(ValueError, context & " must be a JSON object")

  for idText, value in node.pairs:
    var parsedId: uint64
    try:
      parsedId = idText.parseUInt().uint64
    except ValueError:
      raise newException(ValueError, context & " contains an invalid string ID: " & idText)
    if parsedId > uint32.high.uint64:
      raise newException(ValueError, context & " contains an out-of-range string ID: " & idText)
    target[parsedId.uint32] = value.lineFromJson(context & "[" & idText & "]")

proc decodeTranslationJson*(path: string): TranslationIndex =
  result = newTranslationIndex()
  let root = parseFile(path)
  if root.kind != JObject:
    raise newException(ValueError, "Translation JSON root must be an object")

  let hasSections = root.hasKey("tlkstrings") or root.hasKey("files")
  if root.hasKey("tlkstrings"):
    parseIdMap(root["tlkstrings"], result.byId, "tlkstrings")
  elif not hasSections:
    # Compact master form: {"1138510444": "Translated line"}
    parseIdMap(root, result.byId, "translation root")

  if root.hasKey("files"):
    let files = root["files"]
    if files.kind != JObject:
      raise newException(ValueError, "files must be a JSON object")
    for fileKey, idNode in files.pairs:
      let normalized = fileKey.normalizeResourceKey()
      let fileEntries = newTable[uint32, string]()
      parseIdMap(idNode, fileEntries, "files[" & fileKey & "]")
      result.byFile[normalized] = fileEntries

proc findTranslation*(translations: TranslationIndex, resourceKey: string,
                      id: uint32): tuple[found: bool, line: string] =
  if translations == nil:
    return (false, "")

  let normalized = resourceKey.normalizeResourceKey()
  var candidates = @[normalized]
  let arrow = normalized.rfind(" -> ")
  if arrow >= 0:
    candidates.add(normalized[(arrow + 4) .. ^1])
  let basename = normalized.extractFilename()
  if basename != normalized:
    candidates.add(basename)

  for candidate in candidates:
    if translations.byFile.hasKey(candidate) and translations.byFile[candidate].hasKey(id):
      return (true, translations.byFile[candidate][id])

  if translations.byId.hasKey(id):
    return (true, translations.byId[id])
  (false, "")

proc encodeDiscoveryJson*(discovered: DiscoveryIndex, path: string) =
  ## IDs whose source text is consistent across all resources use the compact
  ## global section. Conflicting IDs are emitted under their resource keys.
  var grouped = initTable[uint32, seq[tuple[resource: string, entry: TlkEntry]]]()
  for resource, entries in discovered.pairs:
    for id, entry in entries.pairs:
      grouped.mgetOrPut(id, @[]).add((resource, entry))

  var globalNode = newJObject()
  var filesNode = newJObject()

  var ids: seq[uint32]
  for id in grouped.keys:
    ids.add(id)
  ids.sort()

  for id in ids:
    var occurrences = grouped[id]
    occurrences.sort(proc(a, b: auto): int = cmp(a.resource, b.resource))
    var consistent = true
    let firstLine = occurrences[0].entry.line
    for occurrence in occurrences:
      if occurrence.entry.line != firstLine:
        consistent = false
        break

    if consistent:
      var entryNode = newJObject()
      entryNode["line"] = newJString(firstLine)
      entryNode["node_path"] = newJString(occurrences[0].entry.node_path)
      globalNode[$id] = entryNode
    else:
      for occurrence in occurrences:
        if not filesNode.hasKey(occurrence.resource):
          filesNode[occurrence.resource] = newJObject()
        var entryNode = newJObject()
        entryNode["line"] = newJString(occurrence.entry.line)
        entryNode["node_path"] = newJString(occurrence.entry.node_path)
        filesNode[occurrence.resource][$id] = entryNode

  var root = newJObject()
  root["tlkstrings"] = globalNode
  if filesNode.len > 0:
    root["files"] = filesNode
  writeFile(path, root.pretty())
