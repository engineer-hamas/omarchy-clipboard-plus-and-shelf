import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory
import "ClipboardShelf.js" as ClipboardShelf

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property bool opened: false
  property bool shelfMode: false
  property bool deleteShelfConfirmOpen: false
  property string filterText: ""
  property string typeFilter: "all"
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool clearConfirmOpen: false
  property bool previewExpanded: false
  property bool editorOpen: false
  property string editorError: ""
  property string editorAcceptedText: ""
  property bool editorTextGuardActive: false
  property bool doubleHistoryWriteNewline: false
  property bool pendingEditedCopyOnly: false
  property bool pendingEditedAction: false
  property bool pendingEditedSave: false
  property bool historyWritePending: false
  property bool historyWriteReportedSaved: false
  property bool historyWriteFailed: false
  property var historyWriteExpected: null
  property var history: []
  property string historyStatus: "loading"
  property bool historyContainsOversized: false
  property string historyError: ""
  property bool historyReadInFlight: false
  property bool historyReadPending: false
  property bool historyReadTimedOut: false

  property string expandedKind: ""
  property string expandedText: ""
  property string expandedImage: ""
  property string expandedColor: ""
  property bool expandedTruncated: false
  property int expandedTotalLength: 0

  property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"

  property var shelves: []
  property string shelvesStatus: "loading"
  property bool shelvesContainsOversized: false
  property string shelvesError: ""
  property bool shelfReadInFlight: false
  property bool shelfReadPending: false
  property bool shelfReadTimedOut: false
  property bool shelfWritePending: false
  property bool shelfWriteReportedSaved: false
  property bool shelfWriteFailed: false
  property var shelfWriteExpected: null
  property bool shelfDoubleWriteNewline: false
  property int activeShelfIndex: 0
  property int savedHistorySelectedIndex: 0
  property int savedShelfSelectedIndex: 0
  property string shelfNotice: ""
  property bool shelfRenaming: false

  property string shelfPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-shelf.json"
  readonly property int shelfLimit: ClipboardShelf.maxItemsPerShelf
  readonly property int shelfMaxCount: ClipboardShelf.maxShelves
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(38), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Math.max(Style.space(28), Style.font.caption + Style.spacing.controlPaddingY)
  property int cardWidth: Math.min(Style.space(940), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.font.caption + Style.spacing.rowPaddingX * 2)
  readonly property int historyLimit: ClipboardHistory.maxHistoryEntries
  property int displayLimit: 60

  readonly property var typeFilters: ["all", "text", "images", "colors"]

  readonly property var activeModel: root.shelfMode ? shelfModel : displayModel
  readonly property int viewCount: root.shelfMode ? shelfModel.count : displayModel.count
  readonly property bool modalOpen: root.clearConfirmOpen || root.deleteShelfConfirmOpen

  function viewItemAt(index) {
    if (index < 0 || index >= root.activeModel.count) return null
    return root.activeModel.get(index)
  }

  function open(payloadJson) {
    root.cancelEditedHistoryAction()
    root.opened = true
    root.filterText = ""
    root.typeFilter = "all"
    root.selectedIndex = 0
    root.cursorActive = true
    root.previewExpanded = false
    root.editorOpen = false
    root.editorError = ""
    root.editorAcceptedText = ""
    textEditor.text = ""
    root.shelfMode = false
    root.deleteShelfConfirmOpen = false
    root.shelfRenaming = false
    root.shelfNotice = ""
    root.savedHistorySelectedIndex = 0
    root.savedShelfSelectedIndex = 0
    root.disarmPointer()
    root.rebuildActiveView()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.cancelEditedHistoryAction()
    root.cancelClearHistory(false)
    root.cancelDeleteShelf(false)
    root.previewExpanded = false
    root.editorOpen = false
    root.shelfRenaming = false
    root.editorError = ""
    textEditor.text = ""
    root.opened = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  function applyHistoryResult(result) {
    root.historyStatus = result.status
    root.historyContainsOversized = !!result.containsOversized
    root.history = result.entries
    if (result.status !== "ok") {
      root.cancelEditedHistoryAction()
      root.editorOpen = false
      root.editorError = ""
      root.editorAcceptedText = ""
      textEditor.text = ""
    } else if (!root.historyContainsOversized) {
      root.historyError = ""
    }
    if (root.opened) root.rebuildActiveView()
  }

  function resetHistoryWrite() {
    root.historyWritePending = false
    root.historyWriteReportedSaved = false
    root.historyWriteFailed = false
    root.historyWriteExpected = null
  }

  function resolveHistoryResult(result) {
    if (!root.historyWritePending) {
      root.applyHistoryResult(result)
      return
    }
    // Quickshell 0.3.1 may report saved after an atomic commit failure.
    // Only a bounded reread matching the expected history confirms the write.
    var disposition = ClipboardHistory.historyWriteDisposition(
      result,
      root.historyWriteExpected,
      root.historyWriteReportedSaved,
      root.historyWriteFailed
    )
    if (disposition === "pending") return

    var writeSucceeded = disposition === "confirmed"
    var shouldReport = root.pendingEditedAction
    root.resetHistoryWrite()

    if (writeSucceeded) {
      root.applyHistoryResult(result)
      root.completeEditedHistoryAction()
      return
    }

    root.pendingEditedSave = false
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
    root.applyHistoryResult(result)
    if (shouldReport && root.editorOpen)
      root.editorError = "Could not confirm the edited clipboard text on disk"
    else
      root.historyError = "Could not confirm the clipboard history update on disk"
  }

  function loadHistory(raw) {
    root.resolveHistoryResult(ClipboardHistory.parseHistory(raw))
  }

  function refuseHistory(status) {
    root.resolveHistoryResult({ status: status, entries: [] })
  }

  function emptyHistoryText() {
    if (root.historyStatus === "loading") return "Loading clipboard history…"
    if (root.historyStatus === "oversized") return "Clipboard history is too large"
    if (root.historyStatus === "unreadable") return "Clipboard history is unavailable"
    if (root.historyStatus === "invalid") return "Clipboard history is invalid"
    if (root.history.length === 0) return "Clipboard is empty"
    if (!root.filterText) return "No entries for this filter"
    return "No matches for “" + root.filterText + "”"
  }

  function scheduleHistoryReload() {
    root.historyReadPending = true
    historyReloadTimer.restart()
  }

  function startHistoryRead() {
    if (root.historyReadInFlight) return

    root.historyReadPending = false
    root.historyReadTimedOut = false
    root.historyReadInFlight = true
    historyReadProcess.command = [
      "head",
      "-c",
      String(ClipboardHistory.maxHistoryFileBytes + 1),
      "--",
      root.historyPath
    ]
    historyReadProcess.running = true
    historyReadWatchdog.restart()
  }

  function finishHistoryRead(exitCode) {
    if (!root.historyReadInFlight) return

    historyReadWatchdog.stop()
    root.historyReadInFlight = false
    if (root.historyReadPending) {
      historyReloadTimer.restart()
      return
    }

    if (root.historyReadTimedOut || exitCode !== 0) {
      root.refuseHistory("unreadable")
    } else if (historyReadOutput.data.byteLength > ClipboardHistory.maxHistoryFileBytes) {
      root.refuseHistory("oversized")
    } else {
      root.loadHistory(historyReadOutput.text)
    }
  }

  function saveHistory() {
    if (root.historyActionBlocked()) return false
    if (root.historyStatus !== "ok") {
      root.historyError = "Clipboard history is unavailable; reload before modifying it"
      return false
    }

    // With preload disabled, FileView compares against its own last write.
    // Alternate legal JSON whitespace so an external change can always be overwritten.
    var serialized = ClipboardHistory.serializeHistory(
      root.history,
      root.historyLimit,
      root.doubleHistoryWriteNewline ? 2 : 1
    )
    if (serialized.status !== "ok") {
      root.historyError = serialized.containsOversized
        ? "History with oversized entries can only be cleared or changed in the stock manager"
        : "Clipboard history exceeds its size limit"
      return false
    }

    root.doubleHistoryWriteNewline = !root.doubleHistoryWriteNewline
    root.historyError = ""
    root.historyContainsOversized = false
    historyFile.setText(serialized.text)
    root.historyWriteExpected = root.history
    root.historyWriteReportedSaved = false
    root.historyWriteFailed = false
    root.historyWritePending = true
    return true
  }

  function historyActionBlocked() {
    if (root.historyWritePending) {
      root.historyError = "Clipboard history update is still being confirmed"
      return true
    }
    if (root.historyReadPending || root.historyReadInFlight) {
      root.historyError = "Clipboard history reload is still in progress"
      return true
    }
    return false
  }

  function shelfValidateItems(items) {
    return ClipboardHistory.validateHistory(items, root.shelfLimit, false)
  }

  function activeShelf() {
    if (!Array.isArray(root.shelves) || root.shelves.length === 0)
      return { name: "Default", items: [] }
    var index = root.activeShelfIndex
    if (index < 0 || index >= root.shelves.length) index = 0
    return root.shelves[index]
  }

  function activeShelfName() {
    return String(root.activeShelf().name || "Default")
  }

  function activeShelfItems() {
    var items = root.activeShelf().items
    return Array.isArray(items) ? items : []
  }

  function shelfWritable() {
    return root.shelvesStatus === "ok"
        && !root.shelfWritePending
        && !root.shelfReadPending
        && !root.shelfReadInFlight
  }

  function applyShelvesResult(result) {
    root.shelvesStatus = result.status
    root.shelvesContainsOversized = !!result.containsOversized
    root.shelves = Array.isArray(result.shelves) ? result.shelves : []
    root.shelves = ClipboardShelf.ensureShelf(root.shelves)
    if (root.activeShelfIndex > root.shelves.length - 1) root.activeShelfIndex = root.shelves.length - 1
    if (root.shelfMode && root.selectedIndex > root.activeShelfItems().length - 1)
      root.selectedIndex = Math.max(0, root.activeShelfItems().length - 1)
    if (result.status !== "ok") {
      root.shelfRenaming = false
      root.editorOpen = false
      root.editorError = ""
    } else if (!root.shelvesContainsOversized) {
      root.shelvesError = ""
    }
    if (root.opened && root.shelfMode) root.rebuildShelfDisplay()
  }

  function resetShelfWrite() {
    root.shelfWritePending = false
    root.shelfWriteReportedSaved = false
    root.shelfWriteFailed = false
    root.shelfWriteExpected = null
  }

  function resolveShelvesResult(result) {
    if (!root.shelfWritePending) {
      root.applyShelvesResult(result)
      return
    }
    var disposition = ClipboardShelf.shelfWriteDisposition(
      result,
      root.shelfWriteExpected,
      root.shelfWriteReportedSaved,
      root.shelfWriteFailed
    )
    if (disposition === "pending") return

    var writeSucceeded = disposition === "confirmed"
    root.resetShelfWrite()
    if (writeSucceeded) {
      root.applyShelvesResult(result)
      return
    }
    root.applyShelvesResult(result)
    root.shelvesError = "Could not confirm the shelf update on disk"
  }

  function loadShelves(raw) {
    var text = String(raw || "")
    if (text.trim().length === 0) {
      root.bootstrapShelf()
      return
    }
    root.resolveShelvesResult(ClipboardShelf.validateShelves(text, root.shelfValidateItems))
  }

  function refuseShelves(status) {
    root.resolveShelvesResult({ status: status, shelves: [], containsOversized: false })
  }

  function bootstrapShelf() {
    root.shelvesStatus = "ok"
    root.shelves = ClipboardShelf.ensureShelf(root.shelves)
    root.shelvesError = ""
    root.saveShelves()
    if (root.opened && root.shelfMode) root.rebuildShelfDisplay()
  }

  function emptyShelfText() {
    if (root.shelvesStatus === "loading") return "Loading shelves…"
    if (root.shelvesStatus === "oversized") return "A shelf is too large"
    if (root.shelvesStatus === "unreadable") return "Shelves are unavailable"
    if (root.shelvesStatus === "invalid") return "Shelf data is invalid"
    if (root.shelves.length === 0) return "No shelves"
    if (root.activeShelfItems().length === 0) return "Shelf “" + root.activeShelfName() + "” is empty"
    if (!root.filterText) return "No items for this filter"
    return "No matches for “" + root.filterText + "”"
  }

  function scheduleShelfReload() {
    root.shelfReadPending = true
    shelfReloadTimer.restart()
  }

  function startShelfRead() {
    if (root.shelfReadInFlight) return

    root.shelfReadPending = false
    root.shelfReadTimedOut = false
    root.shelfReadInFlight = true
    shelfReadProcess.command = [
      "head",
      "-c",
      String(ClipboardShelf.maxShelfFileBytes + 1),
      "--",
      root.shelfPath
    ]
    shelfReadProcess.running = true
    shelfReadWatchdog.restart()
  }

  function finishShelfRead(exitCode) {
    if (!root.shelfReadInFlight) return

    shelfReadWatchdog.stop()
    root.shelfReadInFlight = false
    if (root.shelfReadPending) {
      shelfReloadTimer.restart()
      return
    }

    if (root.shelfReadTimedOut) {
      root.refuseShelves("unreadable")
    } else if (exitCode !== 0) {
      root.bootstrapShelf()
    } else if (shelfReadOutput.data.byteLength > ClipboardShelf.maxShelfFileBytes) {
      root.refuseShelves("oversized")
    } else {
      root.loadShelves(shelfReadOutput.text)
    }
  }

  function saveShelves() {
    if (root.shelvesStatus !== "ok") {
      root.shelvesError = "Shelves are unavailable; reload before modifying them"
      return false
    }
    if (root.shelfWritePending) {
      root.shelvesError = "Shelf update is still being confirmed"
      return false
    }
    if (root.shelfReadPending || root.shelfReadInFlight) {
      root.shelvesError = "Shelf reload is still in progress"
      return false
    }

    var serialized = ClipboardShelf.serializeShelves(
      root.shelves,
      root.shelfValidateItems,
      ClipboardHistory.utf8ByteLength,
      root.shelfDoubleWriteNewline ? 2 : 1
    )
    if (serialized.status !== "ok") {
      root.shelvesError = serialized.containsOversized
        ? "A shelf contains oversized entries"
        : "Shelf data exceeds its size limit"
      return false
    }

    root.shelfDoubleWriteNewline = !root.shelfDoubleWriteNewline
    root.shelvesError = ""
    shelfFile.setText(serialized.text)
    root.shelfWriteExpected = root.shelves
    root.shelfWriteReportedSaved = false
    root.shelfWriteFailed = false
    root.shelfWritePending = true
    return true
  }

  function addSelectedToShelf() {
    if (!root.shelfWritable()) {
      root.shelfNotice = ""
      root.shelvesError = root.shelvesError || "Shelves are not ready yet"
      return
    }
    var row = root.viewItemAt(root.selectedIndex)
    if (!row) return
    if (root.activeShelfItems().length >= root.shelfLimit) {
      root.shelvesError = "Shelf “" + root.activeShelfName() + "” is full (" + root.shelfLimit + " items)"
      return
    }

    var shelfEntry
    if (row.entryType === "image") {
      shelfEntry = { type: "image", path: row.path, mime: row.mime }
    } else if (row.entryType === "oversized") {
      root.shelvesError = "Oversized clipboard text cannot be added to a shelf"
      return
    } else {
      var text = ClipboardHistory.entryText(root.history, row.historyIndex)
      if (!text) {
        root.shelvesError = "This clipboard item cannot be added to a shelf"
        return
      }
      shelfEntry = { type: "text", text: text }
    }

    var previous = root.shelves
    var added = ClipboardHistory.addEntry(root.activeShelfItems(), shelfEntry, root.shelfLimit)
    if (added.status !== "ok") {
      root.shelvesError = added.status === "oversized"
        ? "Adding this item would exceed a size limit"
        : "This item cannot be added to a shelf"
      return
    }

    root.shelves = ClipboardShelf.replaceShelfItems(root.shelves, root.activeShelfIndex, added.entries)
    if (!root.saveShelves()) {
      root.shelves = previous
      return
    }
    root.shelvesError = ""
    root.shelfNotice = "Added to “" + root.activeShelfName() + "”"
    root.rebuildShelfDisplay()
  }

  function shelfRemoveSelected() {
    if (!root.shelfWritable()) return
    var row = root.viewItemAt(root.selectedIndex)
    if (!row) return

    var previous = root.shelves
    var items = root.activeShelfItems()
    var index = row.historyIndex
    if (index < 0 || index >= items.length) return
    root.shelves = ClipboardShelf.replaceShelfItems(
      root.shelves,
      root.activeShelfIndex,
      ClipboardHistory.removeEntryAt(items, index)
    )
    if (!root.saveShelves()) {
      root.shelves = previous
      return
    }

    if (root.viewCount <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= root.viewCount - 1) {
      root.selectedIndex = root.viewCount - 2
    }
    root.shelfNotice = "Removed from “" + root.activeShelfName() + "”"
    root.disarmPointer()
    root.rebuildShelfDisplay()
  }

  function requestDeleteShelf() {
    if (!root.shelfWritable()) return
    deleteShelfConfirm.selectedIndex = 1
    root.deleteShelfConfirmOpen = true
  }

  function cancelDeleteShelf(refocus) {
    root.deleteShelfConfirmOpen = false
    root.disarmPointer()
    if (refocus === undefined || refocus)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmDeleteShelf() {
    if (!root.shelfWritable()) return

    var previous = root.shelves
    root.shelves = ClipboardShelf.removeShelf(root.shelves, root.activeShelfIndex)
    root.shelves = ClipboardShelf.ensureShelf(root.shelves)
    if (root.activeShelfIndex > root.shelves.length - 1) root.activeShelfIndex = root.shelves.length - 1
    if (!root.saveShelves()) {
      root.shelves = previous
      return
    }

    root.selectedIndex = 0
    root.cursorActive = false
    root.shelfNotice = ""
    root.deleteShelfConfirmOpen = false
    root.disarmPointer()
    root.rebuildShelfDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function setShelfMode(on) {
    if (on === root.shelfMode) return
    if (on) {
      root.savedHistorySelectedIndex = root.selectedIndex
      root.shelfMode = true
      root.selectedIndex = Math.min(root.savedShelfSelectedIndex, Math.max(0, root.activeShelfItems().length - 1))
      root.shelfNotice = ""
    } else {
      root.savedShelfSelectedIndex = root.selectedIndex
      root.shelfMode = false
      root.selectedIndex = root.savedHistorySelectedIndex
      root.shelfNotice = ""
    }
    root.previewExpanded = false
    root.editorOpen = false
    root.shelfRenaming = false
    root.rebuildActiveView()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function newShelf() {
    if (!root.shelfWritable()) {
      root.shelvesError = root.shelvesError || "Shelves are not ready yet"
      return
    }
    var created = ClipboardShelf.addShelf(root.shelves)
    if (created.status !== "ok") {
      root.shelvesError = "Maximum of " + root.shelfMaxCount + " shelves reached; delete one first"
      return
    }

    var previous = root.shelves
    root.shelves = created.shelves
    if (!root.saveShelves()) {
      root.shelves = previous
      return
    }

    root.activeShelfIndex = created.index
    root.selectedIndex = 0
    root.cursorActive = false
    if (!root.shelfMode) root.setShelfMode(true)
    else root.rebuildShelfDisplay()
    root.shelfNotice = "Created “" + root.activeShelfName() + "”"
  }

  function cycleShelf(delta) {
    if (root.shelves.length <= 1) return
    var next = (root.activeShelfIndex + delta + root.shelves.length) % root.shelves.length
    root.savedShelfSelectedIndex = root.selectedIndex
    root.activeShelfIndex = next
    root.selectedIndex = 0
    root.shelfNotice = ""
    root.rebuildShelfDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startShelfRename() {
    if (root.shelvesStatus !== "ok") {
      root.shelvesError = "Shelves are not ready to rename yet"
      return
    }
    root.previewExpanded = false
    root.editorError = ""
    root.editorAcceptedText = ""
    root.shelfRenaming = true
    root.editorOpen = true
    textEditor.text = root.activeShelfName()
    editorScroll.contentY = 0
    Qt.callLater(function() {
      textEditor.forceActiveFocus()
      textEditor.cursorPosition = textEditor.length
    })
  }

  function cancelShelfRename() {
    root.shelfRenaming = false
    root.editorOpen = false
    root.editorError = ""
    root.editorAcceptedText = ""
    textEditor.text = ""
    root.shelvesError = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function finishShelfRename() {
    if (!root.shelfWritable()) {
      root.editorError = root.shelvesError || "Shelves are not ready yet"
      return
    }
    var name = ClipboardShelf.normalizedShelfName(textEditor.text)
    if (!name) {
      root.editorError = "Shelf name cannot be blank"
      return
    }
    var previous = root.shelves
    root.shelves = ClipboardShelf.renameShelf(root.shelves, root.activeShelfIndex, name)
    if (!root.saveShelves()) {
      root.shelves = previous
      root.editorError = root.shelvesError || "Could not save the shelf name"
      return
    }
    root.shelfRenaming = false
    root.editorOpen = false
    root.editorError = ""
    root.editorAcceptedText = ""
    textEditor.text = ""
    root.shelvesError = ""
    root.shelfNotice = "Renamed to “" + root.activeShelfName() + "”"
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function pasteWholeShelf() {
    var items = root.activeShelfItems()
    if (items.length === 0) {
      root.shelvesError = "Shelf “" + root.activeShelfName() + "” is empty"
      return
    }
    var textParts = []
    var images = []
    for (var i = 0; i < items.length; i++) {
      var item = ClipboardHistory.normalizeEntry(items[i])
      if (!item) continue
      if (item.type === "image") {
        if (item.path) images.push(item)
      } else if (!item.oversized) {
        textParts.push(item.text || "")
      }
    }
    root.opened = false
    if (textParts.length > 0) {
      Quickshell.execDetached([
        root.omarchyPath + "/bin/omarchy-clipboard-paste-text",
        "--shift-insert",
        textParts.join("\n")
      ])
    }
    for (var j = 0; j < images.length; j++) {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", images[j].mime, images[j].path])
    }
  }

  function rebuildActiveView() {
    if (root.shelfMode) root.rebuildShelfDisplay()
    else root.rebuildDisplay()
  }

  function rebuildShelfDisplay() {
    var rows = ClipboardHistory.displayRows(root.activeShelfItems(), root.filterText, root.displayLimit, root.typeFilter)

    shelfModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      shelfModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        swatchColor: row.color || "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    var maxCount = Math.max(0, shelfModel.count - 1)
    if (shelfModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex > maxCount) root.selectedIndex = maxCount
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function() {
      if (shelfModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function requestClearHistory() {
    if (root.historyActionBlocked()) return
    if (root.historyStatus !== "ok"
        && root.historyStatus !== "oversized"
        && root.historyStatus !== "invalid")
      return
    if (root.history.length === 0 && root.historyStatus === "ok") return
    clearConfirm.selectedIndex = 1
    root.clearConfirmOpen = true
  }

  function cancelClearHistory(refocus) {
    root.clearConfirmOpen = false
    root.disarmPointer()
    if (refocus === undefined || refocus)
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function confirmClearHistory() {
    if (root.historyActionBlocked()) return
    root.history = ClipboardHistory.clearHistory()
    root.historyStatus = "ok"
    root.historyContainsOversized = false
    root.saveHistory()
    root.selectedIndex = 0
    root.cursorActive = false
    root.disarmPointer()
    root.clearConfirmOpen = false
    root.rebuildDisplay()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function removeDisplayIndex(index) {
    if (root.historyActionBlocked()) return
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)

    var previousHistory = root.history
    root.history = ClipboardHistory.removeEntryAt(root.history, row.historyIndex)
    if (!root.saveHistory()) {
      root.history = previousHistory
      return
    }

    if (displayModel.count <= 1) {
      root.selectedIndex = 0
      root.cursorActive = false
    } else if (root.selectedIndex >= displayModel.count - 1) {
      root.selectedIndex = displayModel.count - 2
    }

    root.disarmPointer()
    root.rebuildDisplay()
  }

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(root.history, root.filterText, root.displayLimit, root.typeFilter)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) {
      var row = rows[i]
      displayModel.append({
        entryType: row.entryType,
        fullText: row.fullText,
        previewText: row.previewText,
        previewImage: row.previewImage ? Util.fileUrl(row.previewImage) : "",
        swatchColor: row.color || "",
        path: row.path,
        mime: row.mime,
        historyIndex: row.index
      })
    }

    if (displayModel.count === 0) root.selectedIndex = 0
    else if (root.selectedIndex >= displayModel.count) root.selectedIndex = displayModel.count - 1
    else if (root.selectedIndex < 0) root.selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function selectedRow() {
    return root.viewItemAt(root.selectedIndex)
  }

  function viewTextAt(index) {
    if (root.shelfMode) {
      var items = root.activeShelfItems()
      if (index < 0 || index >= items.length) return ""
      var entry = ClipboardHistory.normalizeEntry(items[index])
      return entry && entry.type === "text" && !entry.oversized ? String(entry.text || "") : ""
    }
    return ClipboardHistory.entryText(root.history, index)
  }

  function viewTextPreview(index, limit) {
    var text = root.viewTextAt(index)
    var max = Number(limit)
    if (isNaN(max) || max <= 0 || text.length <= max)
      return { text: text, truncated: false, totalLength: text.length }
    return { text: text.slice(0, max), truncated: true, totalLength: text.length }
  }

  function select(delta) {
    if (root.viewCount === 0) return
    root.disarmPointer()
    if (!root.cursorActive) {
      root.cursorActive = true
      root.selectedIndex = delta < 0 ? root.viewCount - 1 : 0
    } else {
      root.selectedIndex = (root.selectedIndex + delta + root.viewCount) % root.viewCount
    }
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function selectAbsolute(index) {
    if (root.viewCount === 0) return
    root.disarmPointer()
    root.cursorActive = true
    root.selectedIndex = Math.max(0, Math.min(index, root.viewCount - 1))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildActiveView()
  }

  function setTypeFilter(nextFilter) {
    if (root.typeFilters.indexOf(nextFilter) < 0) return
    root.typeFilter = nextFilter
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildActiveView()
  }

  function cycleTypeFilter(delta) {
    var index = root.typeFilters.indexOf(root.typeFilter)
    root.setTypeFilter(root.typeFilters[(index + delta + root.typeFilters.length) % root.typeFilters.length])
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.activeModel.count) return
    root.applySelected(root.activeModel.get(index))
  }

  function copyIndex(index) {
    if (index < 0 || index >= root.activeModel.count) return
    root.copySelected(root.activeModel.get(index))
  }

  function openIndex(index) {
    if (index < 0 || index >= root.activeModel.count) return
    root.openSelected(root.activeModel.get(index))
  }

  function applySelected(row) {
    if (!row) return
    if (root.shelfMode) {
      root.opened = false
      if (row.entryType === "image") {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
      } else {
        var text = root.viewTextAt(row.historyIndex)
        if (!text) return
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", text])
      }
      return
    }
    if (root.historyActionBlocked()) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", "--history-index", String(row.historyIndex)])
    }
  }

  function copySelected(row) {
    if (!row) return
    if (root.shelfMode) {
      root.opened = false
      if (row.entryType === "image") {
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
      } else {
        var text = root.viewTextAt(row.historyIndex)
        if (!text) return
        Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", text])
      }
      return
    }
    if (root.historyActionBlocked()) return
    root.opened = false
    if (row.entryType === "image") {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-file", "--copy-only", row.mime, row.path])
    } else {
      Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(row.historyIndex)])
    }
  }

  function openSelected(row) {
    if (!row) return
    if (root.shelfMode) return
    if (root.historyActionBlocked()) return
    root.opened = false
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-clipboard-open", "--history-index", String(row.historyIndex)])
  }

  function openExpandedPreview() {
    var row = root.selectedRow()
    if (!row) return
    if (row.entryType === "oversized") {
      var msg = root.shelfMode
        ? "Oversized shelf text cannot be previewed"
        : "Oversized clipboard text cannot be previewed"
      if (root.shelfMode) root.shelvesError = msg
      else root.historyError = msg
      return
    }

    root.expandedKind = row.swatchColor ? "color" : (row.previewImage ? "image" : "text")
    root.expandedImage = row.previewImage || ""
    root.expandedColor = row.swatchColor || ""
    root.expandedText = ""
    root.expandedTruncated = false
    root.expandedTotalLength = 0

    if (root.expandedKind === "text") {
      var preview = root.viewTextPreview(row.historyIndex, 65536)
      root.expandedText = preview.text
      root.expandedTruncated = preview.truncated
      root.expandedTotalLength = preview.totalLength
    }

    root.previewExpanded = true
    expandedTextScroll.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function closeExpandedPreview() {
    root.previewExpanded = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startEditor() {
    if (root.shelfMode) {
      root.startShelfRename()
      return
    }
    var row = root.selectedRow()
    if (!row || row.entryType === "image") return
    if (row.entryType === "oversized") {
      root.historyError = "Oversized clipboard text cannot be edited"
      return
    }

    var text = ClipboardHistory.entryText(root.history, row.historyIndex)
    root.previewExpanded = false
    root.editorError = ""
    root.editorAcceptedText = text
    root.editorOpen = true
    textEditor.text = text
    editorScroll.contentY = 0
    Qt.callLater(function() {
      textEditor.forceActiveFocus()
      textEditor.cursorPosition = textEditor.length
    })
  }

  function cancelEditedHistoryAction() {
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
  }

  function closeEditor() {
    root.cancelEditedHistoryAction()
    if (root.shelfRenaming) root.cancelShelfRename()
    root.editorOpen = false
    root.editorError = ""
    root.editorAcceptedText = ""
    textEditor.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function finishEditing(copyOnly) {
    if (root.shelfMode) {
      root.finishShelfRename()
      return
    }

    if (root.historyActionBlocked()) {
      root.editorError = root.historyError
      return
    }
    if (root.historyStatus !== "ok") {
      root.editorError = "Clipboard history is unavailable; press Ctrl+R before saving"
      return
    }

    var text = textEditor.text
    if (text.trim().length === 0) {
      root.editorError = "Clipboard text cannot be blank"
      return
    }
    if (text.length > ClipboardHistory.maxEntryTextLength) {
      root.editorError = "Clipboard text exceeds the 1 MiB limit"
      return
    }
    if (root.pendingEditedSave) {
      root.editorError = "Clipboard operation already in progress"
      return
    }

    var existingIndex = ClipboardHistory.findTextIndex(root.history, text)
    if (existingIndex === 0) {
      var row = { entryType: "text", historyIndex: 0 }
      root.editorOpen = false
      root.editorError = ""
      root.editorAcceptedText = ""
      textEditor.text = ""
      if (copyOnly) root.copySelected(row)
      else root.applySelected(row)
      return
    }

    var added = ClipboardHistory.addEntry(
      root.history,
      { type: "text", text: text },
      root.historyLimit
    )
    if (added.status !== "ok") {
      root.editorError = added.containsOversized
        ? "History with oversized entries can only be cleared or changed in the stock manager"
        : (added.status === "oversized"
          ? "Clipboard history exceeds its size limit"
          : "Clipboard history is invalid")
      return
    }

    var previousHistory = root.history
    root.history = added.entries
    root.editorError = ""
    if (!root.saveHistory()) {
      root.history = previousHistory
      root.rebuildDisplay()
      root.editorError = root.historyError || "Could not save edited clipboard text"
      return
    }

    root.pendingEditedCopyOnly = copyOnly
    root.pendingEditedAction = true
    root.pendingEditedSave = true
  }

  function completeEditedHistoryAction() {
    if (!root.pendingEditedSave) return

    var shouldInvoke = root.pendingEditedAction
    var copyOnly = root.pendingEditedCopyOnly
    root.pendingEditedSave = false
    root.pendingEditedAction = false
    root.pendingEditedCopyOnly = false
    if (!shouldInvoke) return

    var command = [root.omarchyPath + "/bin/omarchy-clipboard-paste-text"]
    if (copyOnly) command.push("--copy-only")
    command.push("--history-index", "0")

    root.editorOpen = false
    root.editorError = ""
    textEditor.text = ""
    root.opened = false
    Quickshell.execDetached(command)
  }

  Component.onCompleted: {
    root.scheduleHistoryReload()
    root.scheduleShelfReload()
  }

  ListModel { id: displayModel }

  ListModel { id: shelfModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    preload: false
    atomicWrites: true
    printErrors: false
    onFileChanged: root.scheduleHistoryReload()
    onSaved: {
      if (root.historyWritePending) root.historyWriteReportedSaved = true
      root.scheduleHistoryReload()
    }
    onSaveFailed: {
      if (root.historyWritePending) root.historyWriteFailed = true
      root.scheduleHistoryReload()
    }
  }

  FileView {
    id: shelfFile
    path: root.shelfPath
    watchChanges: true
    preload: false
    atomicWrites: true
    printErrors: false
    onFileChanged: root.scheduleShelfReload()
    onSaved: {
      if (root.shelfWritePending) root.shelfWriteReportedSaved = true
      root.scheduleShelfReload()
    }
    onSaveFailed: {
      if (root.shelfWritePending) root.shelfWriteFailed = true
      root.scheduleShelfReload()
    }
  }

  Process {
    id: historyReadProcess
    command: []
    stdout: StdioCollector {
      id: historyReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) { root.finishHistoryRead(exitCode) }
  }

  Process {
    id: shelfReadProcess
    command: []
    stdout: StdioCollector {
      id: shelfReadOutput
      waitForEnd: true
    }
    onExited: function(exitCode, exitStatus) { root.finishShelfRead(exitCode) }
  }

  Timer {
    id: historyReloadTimer
    interval: 75
    repeat: false
    onTriggered: root.startHistoryRead()
  }

  Timer {
    id: historyReadWatchdog
    interval: 5000
    repeat: false
    onTriggered: {
      if (!root.historyReadInFlight) return
      root.historyReadTimedOut = true
      if (historyReadProcess.running) historyReadProcess.signal(9)
      else root.finishHistoryRead(-1)
    }
  }

  Timer {
    id: shelfReloadTimer
    interval: 75
    repeat: false
    onTriggered: root.startShelfRead()
  }

  Timer {
    id: shelfReadWatchdog
    interval: 5000
    repeat: false
    onTriggered: {
      if (!root.shelfReadInFlight) return
      root.shelfReadTimedOut = true
      if (shelfReadProcess.running) shelfReadProcess.signal(9)
      else root.finishShelfRead(-1)
    }
  }


  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.modalOpen ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.clearConfirmOpen) {
            if (clearConfirm.handleKey(event)) event.accepted = true
            return
          }
          if (root.deleteShelfConfirmOpen) {
            if (deleteShelfConfirm.handleKey(event)) event.accepted = true
            return
          }

          var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
          var shift = (event.modifiers & Qt.ShiftModifier) !== 0

          if (root.previewExpanded) {
            if (event.key === Qt.Key_Escape || (ctrl && event.key === Qt.Key_Space)) {
              root.closeExpandedPreview()
              event.accepted = true
            } else if (ctrl && event.key === Qt.Key_E && root.expandedKind === "text") {
              root.startEditor()
              event.accepted = true
            } else if (event.key === Qt.Key_PageUp) {
              expandedTextScroll.contentY = Math.max(0, expandedTextScroll.contentY - expandedTextScroll.height * 0.8)
              event.accepted = true
            } else if (event.key === Qt.Key_PageDown) {
              expandedTextScroll.contentY = Math.min(Math.max(0, expandedTextScroll.contentHeight - expandedTextScroll.height), expandedTextScroll.contentY + expandedTextScroll.height * 0.8)
              event.accepted = true
            }
            return
          }

          if (root.editorOpen) return

          if (event.key === Qt.Key_Escape) {
            if (root.shelfMode) {
              root.setShelfMode(false)
              root.shelfNotice = ""
            } else if (root.filterText) {
              root.setFilter("")
            } else {
              root.close()
            }
            event.accepted = true
          } else if (ctrl && !shift && !root.shelfMode && event.key === Qt.Key_S) {
            root.shelvesError = ""
            root.addSelectedToShelf()
            event.accepted = true
          } else if (ctrl && shift && event.key === Qt.Key_S) {
            root.setShelfMode(!root.shelfMode)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_N) {
            root.newShelf()
            event.accepted = true
          } else if (ctrl && !shift && root.shelfMode && event.key === Qt.Key_Tab) {
            root.cycleShelf(1)
            event.accepted = true
          } else if (ctrl && shift && root.shelfMode && event.key === Qt.Key_Tab) {
            root.cycleShelf(-1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_J) {
            root.select(1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_K) {
            root.select(-1)
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_Space) {
            root.openExpandedPreview()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_E) {
            root.startEditor()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_R) {
            if (root.shelfMode) root.scheduleShelfReload()
            else root.scheduleHistoryReload()
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_1) {
            root.setTypeFilter("all")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_2) {
            root.setTypeFilter("text")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_3) {
            root.setTypeFilter("images")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_4) {
            root.setTypeFilter("colors")
            event.accepted = true
          } else if (ctrl && event.key === Qt.Key_T) {
            root.cycleTypeFilter(shift ? -1 : 1)
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Delete) {
            if (root.shelfMode) {
              if (shift) root.requestDeleteShelf()
              else root.shelfRemoveSelected()
            } else {
              if (shift) root.requestClearHistory()
              else root.removeDisplayIndex(root.selectedIndex)
            }
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-6)
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(6)
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.selectAbsolute(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.selectAbsolute(root.viewCount - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.cursorActive && (event.modifiers & Qt.AltModifier)) {
              if (root.shelfMode) root.pasteWholeShelf()
              else root.openIndex(root.selectedIndex)
            } else if (root.cursorActive && shift) {
              root.copyIndex(root.selectedIndex)
            } else if (root.cursorActive) {
              root.activateIndex(root.selectedIndex)
            } else if (root.viewCount > 0) {
              root.cursorActive = true
            }
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: clearConfirm
          anchors.fill: parent
          opened: root.clearConfirmOpen
          z: 10
          message: "Delete entire clipboard history?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelClearHistory()
          onConfirmed: root.confirmClearHistory()
        }

        ConfirmDialog {
          id: deleteShelfConfirm
          anchors.fill: parent
          opened: root.deleteShelfConfirmOpen
          z: 10
          message: "Delete entire shelf “" + root.activeShelfName() + "”?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDeleteShelf()
          onConfirmed: root.confirmDeleteShelf()
        }
      }

      Column {
        id: normalView
        visible: !root.previewExpanded && !root.editorOpen
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Row {
          width: parent.width
          height: root.headerHeight
          spacing: Style.space(12)

          Text {
            width: parent.width - filterLabel.width - shelfChip.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || (root.shelfMode ? "Search shelf…" : "Search clipboard…")
            textFormat: Text.PlainText
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Item {
            id: shelfChip
            anchors.verticalCenter: parent.verticalCenter
            visible: root.shelfMode
            width: visible ? Math.max(Style.space(84), chipText.implicitWidth + Style.space(20)) : 0
            height: Style.space(26)

            Rectangle {
              anchors.fill: parent
              radius: Math.max(Style.space(4), height * 0.3)
              color: Util.alpha(root.selectedBackground, 0.6)
            }

            Text {
              id: chipText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              text: "SHELF " + (root.activeShelfIndex + 1) + " · " + root.activeShelfName()
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }
          }

          Text {
            id: filterLabel
            anchors.verticalCenter: parent.verticalCenter
            text: root.typeFilter === "all" ? "ALL" : root.typeFilter.toUpperCase()
            color: root.selectedText
            opacity: 0.72
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: parent.width * 0.45
              height: parent.height
              clip: true

              ListView {
                id: resultList
                anchors.fill: parent
                anchors.rightMargin: root.contentMargin
                model: root.activeModel
                clip: true
                spacing: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                  id: row
                  required property int index
                  required property string entryType
                  required property string previewText
                  required property string fullText
                  required property string previewImage
                  required property string swatchColor

                  readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex

                  width: ListView.view.width
                  height: root.rowHeight
                  radius: root.cornerRadius
                  color: hasCursor ? root.selectedBackground : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(12)
                    anchors.topMargin: Style.space(8)
                    anchors.bottomMargin: Style.space(8)
                    spacing: Style.space(10)

                    Rectangle {
                      visible: row.swatchColor.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      radius: Math.max(Style.space(4), height * 0.22)
                      color: row.swatchColor || "transparent"
                      border.width: visible ? Style.normalBorderWidth : 0
                      border.color: root.border
                    }

                    Image {
                      visible: row.swatchColor.length === 0 && row.previewImage.length > 0
                      width: visible ? parent.height : 0
                      height: parent.height
                      source: row.previewImage
                      sourceSize.width: Math.max(1, root.rowHeight)
                      sourceSize.height: Math.max(1, root.rowHeight)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      width: parent.width - ((row.swatchColor.length > 0 || row.previewImage.length > 0) ? parent.height + parent.spacing : 0)
                      height: parent.height
                      text: row.previewText
                      color: row.hasCursor ? root.selectedText : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      opacity: row.entryType === "image" || row.entryType === "file" ? 0.72 : 1
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                      textFormat: Text.PlainText
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                    onClicked: {
                      root.cursorActive = true
                      root.selectedIndex = row.index
                      root.activateIndex(row.index)
                    }
                  }
                }
              }
            }

            Item {
              id: previewPane
              width: parent.width * 0.55
              height: parent.height
              clip: true

              property var activeRow: root.activeModel.count > 0 && root.selectedIndex >= 0 && root.selectedIndex < root.activeModel.count ? root.activeModel.get(root.selectedIndex) : null

              Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.normalBorderWidth
                color: Util.alpha(root.border, 0.28)
              }

              Flickable {
                id: compactTextScroll
                visible: previewPane.activeRow && !previewPane.activeRow.previewImage && !previewPane.activeRow.swatchColor
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                clip: true
                contentWidth: width
                contentHeight: Math.max(height, compactPreviewText.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds

                Text {
                  id: compactPreviewText
                  width: compactTextScroll.width
                  text: previewPane.activeRow ? previewPane.activeRow.fullText : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  wrapMode: Text.WrapAnywhere
                  textFormat: Text.PlainText
                }
              }

              Image {
                visible: previewPane.activeRow && previewPane.activeRow.previewImage
                anchors.fill: parent
                anchors.leftMargin: root.contentMargin
                source: previewPane.activeRow ? previewPane.activeRow.previewImage : ""
                sourceSize.width: Math.max(1, root.cardWidth)
                sourceSize.height: Math.max(1, root.cardHeight)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
              }

              Column {
                visible: previewPane.activeRow && previewPane.activeRow.swatchColor
                anchors.centerIn: parent
                spacing: Style.space(16)

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: Style.space(170)
                  height: width
                  radius: root.cornerRadius
                  color: previewPane.activeRow ? previewPane.activeRow.swatchColor : "transparent"
                  border.width: Style.normalBorderWidth
                  border.color: root.border
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: previewPane.activeRow ? previewPane.activeRow.swatchColor : ""
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: root.viewCount === 0

            Text {
              text: "󰅌"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              text: root.shelfMode ? root.emptyShelfText() : root.emptyHistoryText()
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          text: root.shelfMode
            ? (root.shelfNotice || root.shelvesError || "Ctrl+Shift+S back · Ctrl+N new · Ctrl+Tab switch · Ctrl+E rename · Alt+Enter paste shelf")
            : (root.historyError || (root.shelfNotice ? root.shelfNotice : "Enter paste · Ctrl+J/K move · Ctrl+E edit · Ctrl+Space expand · Ctrl+S to shelf · Ctrl+Shift+S show shelf"))
          textFormat: Text.PlainText
          color: root.foreground
          opacity: (root.shelfMode && (root.shelvesError || root.shelfNotice)) || (root.historyError) ? 0.9 : 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          verticalAlignment: Text.AlignVCenter
        }
      }

      Item {
        id: expandedView
        visible: root.previewExpanded
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: expandedTitle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight
          text: root.expandedKind === "image" ? "Image preview" : root.expandedKind === "color" ? "Color preview" : (root.shelfMode ? "Shelf text preview" : "Text preview")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: expandedTitle.verticalCenter
          text: "Ctrl+Space or Esc to return"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Image {
          visible: root.expandedKind === "image"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: expandedTitle.bottom
          anchors.bottom: parent.bottom
          source: root.expandedImage
          sourceSize.width: Math.max(1, root.cardWidth)
          sourceSize.height: Math.max(1, root.cardHeight)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
        }

        Column {
          visible: root.expandedKind === "color"
          anchors.centerIn: parent
          spacing: Style.space(20)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(Style.space(320), expandedView.width * 0.55)
            height: width
            radius: root.cornerRadius
            color: root.expandedColor || "transparent"
            border.width: Style.normalBorderWidth
            border.color: root.border
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.expandedColor
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }
        }

        Flickable {
          id: expandedTextScroll
          visible: root.expandedKind === "text"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: expandedTitle.bottom
          anchors.bottom: expandedTruncation.top
          clip: true
          contentWidth: width
          contentHeight: Math.max(height, expandedTextItem.implicitHeight)
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: expandedTextItem
            width: expandedTextScroll.width
            text: root.expandedText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
          }
        }

        Text {
          id: expandedTruncation
          visible: root.expandedKind === "text" && root.expandedTruncated
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? root.footerHeight : 0
          text: "Preview capped at 64 KiB; Ctrl+E opens the complete text"
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }
      }

      Item {
        id: editorView
        visible: root.editorOpen
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: editorTitle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight
          text: root.shelfRenaming ? "Rename shelf" : "Edit clipboard text"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          anchors.right: parent.right
          anchors.verticalCenter: editorTitle.verticalCenter
          text: root.shelfRenaming
            ? "Ctrl+Enter save  ·  Esc cancel"
            : "Ctrl+Enter save & paste  ·  Ctrl+Shift+Enter save & copy  ·  Esc cancel"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: editorTitle.bottom
          anchors.bottom: editorErrorText.top
          color: Util.alpha(root.foreground, 0.035)
          radius: root.cornerRadius
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(root.border, 0.5)

          Flickable {
            id: editorScroll
            anchors.fill: parent
            anchors.margins: Style.space(14)
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, textEditor.implicitHeight)
            boundsBehavior: Flickable.StopAtBounds

            TextEdit {
              id: textEditor
              width: editorScroll.width
              height: Math.max(editorScroll.height, implicitHeight)
              color: root.foreground
              selectionColor: root.selectedBackground
              selectedTextColor: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              wrapMode: TextEdit.WrapAnywhere
              textFormat: TextEdit.PlainText
              selectByMouse: true

              onTextChanged: {
                if (root.editorTextGuardActive) return
                var limit = root.shelfRenaming ? ClipboardShelf.maxShelfNameLength : ClipboardHistory.maxEntryTextLength
                var exceedMessage = root.shelfRenaming
                  ? "Shelf name exceeded " + ClipboardShelf.maxShelfNameLength + " characters"
                  : "Clipboard text exceeds the 1 MiB limit"
                if (text.length <= limit) {
                  root.editorAcceptedText = text
                  if (root.editorError === exceedMessage) root.editorError = ""
                  return
                }

                root.editorTextGuardActive = true
                text = root.editorAcceptedText
                root.editorTextGuardActive = false
                root.editorError = exceedMessage
              }

              onCursorRectangleChanged: {
                if (cursorRectangle.y < editorScroll.contentY)
                  editorScroll.contentY = cursorRectangle.y
                else if (cursorRectangle.y + cursorRectangle.height > editorScroll.contentY + editorScroll.height)
                  editorScroll.contentY = cursorRectangle.y + cursorRectangle.height - editorScroll.height
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                if (event.key === Qt.Key_Escape) {
                  root.closeEditor()
                  event.accepted = true
                } else if (ctrl && shift && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.finishEditing(true)
                  event.accepted = true
                } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                  root.finishEditing(false)
                  event.accepted = true
                }
              }
            }
          }
        }

        Text {
          id: editorErrorText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.editorError ? root.footerHeight : 0
          text: root.editorError
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }
}
