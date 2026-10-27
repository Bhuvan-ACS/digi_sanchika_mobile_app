# Document gallery implementation brief

Objective: implement a reusable Flutter document gallery/card component for the existing Digi Sanchika app. Apply it to Library, folder documents, and Shared with me document lists without changing their data loading, navigation, or action callbacks.

Existing app context:
- Flutter app rooted at `E:/projects/digi_sanchika_mobile_app`.
- Existing duplicated implementations are in `lib/presentations/Screens/document_library.dart` and `lib/presentations/Screens/shared_files_screen.dart`.
- Existing reusable `lib/widgets/document_card.dart` is also a candidate for replacement/extension.
- Existing folder screens include `lib/presentations/Screens/folder_screen.dart`, `shared_folder_screen.dart`, and `shared_folder_folder_screen.dart`.
- Preserve current Document model and all service/action callbacks.

Required UX:
- Exactly three modes: list (one column), grid2 (two columns), grid3 (three columns). Provide a shared enum/API or compatible adapters so each host screen can keep its current state.
- 12-16 px spacing, responsive sizing, white 16 px cards, soft shadows, no overflow.
- List collapsed card is horizontal: file icon, one-line ellipsized title, date/size, overflow menu, down chevron.
- Grid collapsed cards are compact vertical cards: icon top-left, menu and down chevron top-right, title and date/size below.
- Grid expansion MUST be a floating dialog/overlay with fixed consistent internal layout; it must not expand inline in a grid cell.
- List expansion can be inline. Expanded layout is identical in all modes: header icon/title/date/up chevron, divider, four detail rows (Owner with pale-blue B avatar + bhuvan; Path pale-green pill; Classification pale-purple pill; Sharing pale-orange pill), divider, exactly three equal pill actions View/Pale Blue, Versions/Pale Green, Download/Pale Orange.
- Keep existing host callbacks. If an existing callback is Share/Delete, preserve it through overflow menu or host-provided action; do not silently remove functionality.
- Folder cards remain separate; document cards within folders must use the same gallery component. In sub-document folder view, retain/add a subfolders button at the right end of the folder card bottom on hover/desktop and tap-safe behavior on mobile.
- Remove visual duplicates by routing the three document contexts through the shared component.

Implementation constraints:
- Use current app theme/colors and FileTypeIcon where practical.
- Do not alter service APIs or document model.
- Keep changes focused in `lib/widgets/` and the affected document/folder screens.
- Verify with `flutter analyze` and format changed Dart files.
