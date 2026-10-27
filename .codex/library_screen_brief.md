# Library screen iteration

Implement the Library tab content in the existing Flutter app at `E:/projects/digi_sanchika_mobile_app`.

Target file: `lib/presentations/Screens/document_library.dart`. Preserve all existing loading, search, filtering, document preview, versions, share, and download callbacks. Preserve the existing `ResponsiveDocumentGallery` card appearance and behavior; only compose it into the new page shell.

Requirements:
- Exactly two swipeable tabs: Documents and Folders, using DefaultTabController/TabBarView.
- Custom segmented pill control (light grey outer pill, active white pill with shadow), no underline tab indicator.
- Header area: Library title only if this screen owns the header; avoid duplicating HomePage's shell header. Search pill with current PillSearchField and Filter pill beside it.
- Under search, row with document count and 3-state layout toggle (list, 2 columns, 3 columns). Reuse current layout state and `LayoutCapsule` where appropriate, but ensure exactly these three modes are visible.
- Documents tab renders current filtered documents through `ResponsiveDocumentGallery`; list/grid expand behavior must remain unchanged.
- Folders tab renders current library folders using existing folder data and navigation/action behavior, with a clean list/grid placeholder-style card if needed.
- Ensure the tab view and each tab content are scrollable without RenderFlex overflow. Bottom padding must account for the app's FAB/bottom navigation.
- Keep the existing filtering/search mechanics and offline states.
- Do not change services or models.

The app's HomePage may already render a Library title and bottom navigation, so inspect the parent before adding duplicate chrome. Format changed Dart files and run targeted flutter analyze.
