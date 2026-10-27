import Foundation
import Observation

/// The Swift read model of the core's state. Views read it directly; only the
/// changes `CrestCore` receives update it, each through its own
/// `apply(to:)` in a `Changes/Area/Change+CoreState.swift` file. It is
/// observable per entity: each workspace, Space, tab, folder and window is
/// an object of its own that notifies only when one of its values really
/// changes.
///
/// Every value is stored before it is announced, so a view that renders
/// while a change is announced reads the new value; see
/// `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class CoreState {
    // MARK: - Types

    /// The page one tab's surfaces read, observed on that tab alone: a page's
    /// live state notifies the readers of its tab instead of every reader of
    /// every page.
    @MainActor
    @Observable
    fileprivate final class TabPageSlot: BrowserStoreFirstObservable {
        var page: PageStateModel? {
            get {
                access(keyPath: \.page)
                return pageStorage
            }
            set {
                guard pageStorage !== newValue else { return }
                pageStorage = newValue
                withMutation(keyPath: \.page) {}
            }
        }
        @ObservationIgnored private var pageStorage: PageStateModel?

        init() {}
    }

    // MARK: - Variables

    /// Each workspace attached to this device, by workspace. The dictionary
    /// changes only when a workspace joins or leaves.
    var workspaces: [UUID: WorkspaceModel] { observed(\.workspacesStorage, as: \.workspaces) }
    @ObservationIgnored var workspacesStorage: [UUID: WorkspaceModel] = [:]
    /// The images tabs wear, which the platform keeps and the core never sees.
    let favicons = FaviconAssets()
    /// This run's download records, newest first.
    var downloads: [DownloadState] {
        get { observed(\.downloadsStorage, as: \.downloads) }
        set { publish(newValue, into: \.downloadsStorage, as: \.downloads) }
    }
    @ObservationIgnored private var downloadsStorage: [DownloadState] = []
    /// What each open window shows, by window. The dictionary changes only
    /// when a window opens or closes.
    var windows: [UUID: WindowStateModel] { observed(\.windowsStorage, as: \.windows) }
    @ObservationIgnored var windowsStorage: [UUID: WindowStateModel] = [:]
    /// Each page this device hosts, by page: its owner, its engine, where it
    /// stands there and its live state. The dictionary changes only when a
    /// page opens or goes, so a page's new title redraws only its readers.
    var pages: [UUID: PageStateModel] { observed(\.pagesStorage, as: \.pages) }
    @ObservationIgnored var pagesStorage: [UUID: PageStateModel] = [:]
    /// The page each tab shows, by tab, so a tab's surfaces read their own page
    /// instead of searching every page. Each slot is observed on its own. A
    /// slot is made the first time a tab asks for its page, so the reader
    /// hears of the page that arrives later.
    @ObservationIgnored private var tabPages: [UUID: TabPageSlot] = [:]
    /// The tab each open page shows, by page, so a page a change gives another
    /// tab leaves the slot it was read from.
    @ObservationIgnored private var pageTabs: [UUID: UUID] = [:]
    /// The engines this device registered, with what each supports and which
    /// one new pages open on, as the core last published them. Nil until an
    /// engine registers.
    var engines: EngineRoster? {
        get { observed(\.enginesStorage, as: \.engines) }
        set { publish(newValue, into: \.enginesStorage, as: \.engines) }
    }
    @ObservationIgnored private var enginesStorage: EngineRoster?
    /// Ordinary engine choices on this device. Private site choices are absent.
    var enginePreferences: EnginePreferences {
        get { observed(\.enginePreferencesStorage, as: \.enginePreferences) }
        set { publish(newValue, into: \.enginePreferencesStorage, as: \.enginePreferences) }
    }
    @ObservationIgnored private var enginePreferencesStorage = EnginePreferences(defaultEngine: nil, rules: [])
    /// Whether agents may use Crest on this device, whether they may run
    /// scripts in pages, the Spaces they may reach and the agents the person
    /// allowed.
    var agentPreferences: AgentPreferences {
        get { observed(\.agentPreferencesStorage, as: \.agentPreferences) }
        set { publish(newValue, into: \.agentPreferencesStorage, as: \.agentPreferences) }
    }
    @ObservationIgnored private var agentPreferencesStorage = AgentPreferences(
        isOn: false, runsScripts: false, spaceIDs: [], agents: [])
    /// The agents connected now, with the tabs each uses.
    var agentSessions: [AgentSessionState] {
        get { observed(\.agentSessionsStorage, as: \.agentSessions) }
        set { publish(newValue, into: \.agentSessionsStorage, as: \.agentSessions) }
    }
    @ObservationIgnored private var agentSessionsStorage: [AgentSessionState] = []
    /// The newest file revision the core has on disk, counting the stored
    /// session's edits and this device's saved windows; zero before its first
    /// save and for a core that keeps nothing.
    var savedRevision: Int64 {
        get { observed(\.savedRevisionStorage, as: \.savedRevision) }
        set { publish(newValue, into: \.savedRevisionStorage, as: \.savedRevision) }
    }
    @ObservationIgnored private var savedRevisionStorage: Int64 = 0
    /// Why the core's last save failed, until a later save succeeds.
    var storageFailure: StorageFailure? {
        get { observed(\.storageFailureStorage, as: \.storageFailure) }
        set { publish(newValue, into: \.storageFailureStorage, as: \.storageFailure) }
    }
    @ObservationIgnored private var storageFailureStorage: StorageFailure?
    /// Why the core could not stage the session's latest edits for sync, until
    /// a later stage succeeds.
    var syncStagingFailure: SyncStagingFailure? {
        get { observed(\.syncStagingFailureStorage, as: \.syncStagingFailure) }
        set { publish(newValue, into: \.syncStagingFailureStorage, as: \.syncStagingFailure) }
    }
    @ObservationIgnored private var syncStagingFailureStorage: SyncStagingFailure?
    /// What the stored session's sync journal holds, as the core last
    /// published it: its records and those waiting to upload. Nil until the
    /// core attaches the journal, and for a core that keeps nothing.
    var syncJournal: SyncJournalChanged? {
        get { observed(\.syncJournalStorage, as: \.syncJournal) }
        set { publish(newValue, into: \.syncJournalStorage, as: \.syncJournal) }
    }
    @ObservationIgnored private var syncJournalStorage: SyncJournalChanged?
    /// The site permission choices each Space keeps, in the order the settings
    /// list them, as the core last published them. A Space missing here keeps
    /// none.
    var sitePermissions: [UUID: [SitePermissionRecordState]] {
        get { observed(\.sitePermissionsStorage, as: \.sitePermissions) }
        set { publish(newValue, into: \.sitePermissionsStorage, as: \.sitePermissions) }
    }
    @ObservationIgnored private var sitePermissionsStorage: [UUID: [SitePermissionRecordState]] = [:]
    /// Advances with every site permission change the core publishes, so a
    /// view that asks the core for a decision redraws when any choice changes.
    var sitePermissionRevision: UInt64 {
        get { observed(\.sitePermissionRevisionStorage, as: \.sitePermissionRevision) }
        set { publish(newValue, into: \.sitePermissionRevisionStorage, as: \.sitePermissionRevision) }
    }
    @ObservationIgnored private var sitePermissionRevisionStorage: UInt64 = 0
    /// The keys each command this device offers answers to, in the order the
    /// settings list them, as the core last published them.
    var shortcutBindings: [ShortcutBinding] {
        get { observed(\.shortcutBindingsStorage, as: \.shortcutBindings) }
        set { publish(newValue, into: \.shortcutBindingsStorage, as: \.shortcutBindings) }
    }
    @ObservationIgnored private var shortcutBindingsStorage: [ShortcutBinding] = []
    /// The same bindings, by command.
    var shortcuts: [ShortcutCommand: ShortcutBinding] {
        get { observed(\.shortcutsStorage, as: \.shortcuts) }
        set { publish(newValue, into: \.shortcutsStorage, as: \.shortcuts) }
    }
    @ObservationIgnored private var shortcutsStorage: [ShortcutCommand: ShortcutBinding] = [:]
    /// Whether the person changed any shortcut, including one this device
    /// does not offer.
    var shortcutsAreCustomized: Bool {
        get { observed(\.shortcutsAreCustomizedStorage, as: \.shortcutsAreCustomized) }
        set { publish(newValue, into: \.shortcutsAreCustomizedStorage, as: \.shortcutsAreCustomized) }
    }
    @ObservationIgnored private var shortcutsAreCustomizedStorage = false
    /// This device's link preferences, as the core last published them. Nil
    /// only until the link preference store adopts them, at launch.
    var linkPreferences: LinkPreferences? {
        get { observed(\.linkPreferencesStorage, as: \.linkPreferences) }
        set { publish(newValue, into: \.linkPreferencesStorage, as: \.linkPreferences) }
    }
    @ObservationIgnored private var linkPreferencesStorage: LinkPreferences?
    /// This device's search catalog, its providers as the device searches with
    /// them and its default search, as the core last published them. Nil only
    /// until the launch restores the catalog.
    var searchCatalog: SearchCatalogChanged? {
        get { observed(\.searchCatalogStorage, as: \.searchCatalog) }
        set { publish(newValue, into: \.searchCatalogStorage, as: \.searchCatalog) }
    }
    @ObservationIgnored private var searchCatalogStorage: SearchCatalogChanged?
    /// The manual setup this device holds, as the core last published it, or
    /// nil while none is in progress.
    var setupDraft: SetupDraft? {
        get { observed(\.setupDraftStorage, as: \.setupDraft) }
        set { publish(newValue, into: \.setupDraftStorage, as: \.setupDraft) }
    }
    @ObservationIgnored private var setupDraftStorage: SetupDraft?
    /// Setup on this device, as the core last published it, or nil while it
    /// is not open.
    var setupFlow: SetupFlowState? {
        get { observed(\.setupFlowStorage, as: \.setupFlow) }
        set { publish(newValue, into: \.setupFlowStorage, as: \.setupFlow) }
    }
    @ObservationIgnored private var setupFlowStorage: SetupFlowState?
    /// Whether this device has completed setup, as the core last published
    /// it. Nil until the launch adopts it.
    var setupCompleted: Bool? {
        get { observed(\.setupCompletedStorage, as: \.setupCompleted) }
        set { publish(newValue, into: \.setupCompletedStorage, as: \.setupCompleted) }
    }
    @ObservationIgnored private var setupCompletedStorage: Bool?
    /// This process's access to each Space profile that holds a grant or is
    /// waiting on the device owner, as the core last published it. A profile
    /// missing here holds no grant.
    var spaceAccess: [BrowserSpaceRuntimeAssignment: SpaceLockChanged] {
        observed(\.spaceAccessStorage, as: \.spaceAccess)
    }
    @ObservationIgnored var spaceAccessStorage: [BrowserSpaceRuntimeAssignment: SpaceLockChanged] = [:]

    // MARK: - Actions - Pages

    /// The page tab `tabID` shows, observed through that tab alone. Nil while
    /// the tab has no page or its page keeps no engine page, such as one that
    /// failed to open.
    func page(ofTab tabID: UUID) -> PageStateModel? {
        guard let page = slot(forTab: tabID).page, page.phase.holdsEnginePage else { return nil }
        return page
    }

    /// Takes the page the core just opened into the pages map, and points the
    /// slot of the tab the page shows at it.
    func pageOpened(_ page: PageStateModel) {
        publish(page, forKey: page.id, into: \.pagesStorage, as: \.pages)
        move(page, toTab: page.tabID)
    }

    /// Takes the core's next values for a page it already holds, and moves the
    /// page's slot when the change gives the page another tab.
    func pageChanged(_ page: PageState) {
        guard let held = pagesStorage[page.id] else { return }
        held.update(page)
        move(held, toTab: held.tabID)
    }

    /// Forgets a page the core removed, and the slot of the tab that showed
    /// it. A slot another page took over keeps that page.
    func pageRemoved(_ pageID: UUID) {
        let removed = pagesStorage[pageID]
        publish(nil, forKey: pageID, into: \.pagesStorage, as: \.pages)
        guard let tabID = pageTabs.removeValue(forKey: pageID) else { return }
        guard let removed, tabPages[tabID]?.page === removed else { return }
        tabPages[tabID]?.page = nil
    }

    /// The slot tab `tabID` reads, made when the tab first asks for its page
    /// so its readers observe the page that arrives later.
    private func slot(forTab tabID: UUID) -> TabPageSlot {
        if let held = tabPages[tabID] { return held }
        let slot = TabPageSlot()
        tabPages[tabID] = slot
        return slot
    }

    /// Points the slot of `tabID` at `page`, clearing the slot of the tab the
    /// page showed before a change gave it another.
    private func move(_ page: PageStateModel, toTab tabID: UUID?) {
        if let previous = pageTabs[page.id], previous != tabID,
            tabPages[previous]?.page === page
        {
            tabPages[previous]?.page = nil
        }
        guard let tabID else {
            pageTabs.removeValue(forKey: page.id)
            return
        }
        pageTabs[page.id] = tabID
        slot(forTab: tabID).page = page
    }
}

extension CoreState: BrowserStoreFirstObservable {}
