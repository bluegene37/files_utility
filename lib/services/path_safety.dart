import 'dart:io';
import 'package:path/path.dart' as p;

/// Reports whether [candidate] really lives at or inside [root] once every
/// symbolic link along the way has been resolved.
///
/// The file walkers deliberately list with `followLinks: false` and then
/// handle [Link] entities themselves. Without this check a single link
/// inside the folder the user selected lets a run walk straight out of it
/// and act on files elsewhere on the machine.
///
/// Returns `false` when the path cannot be resolved: an operation that
/// deletes or moves files must fail closed, not guess.
Future<bool> resolvesWithinRoot(String root, String candidate) async {
  try {
    final resolvedRoot = await Directory(root).resolveSymbolicLinks();
    final resolvedCandidate = await Link(candidate).resolveSymbolicLinks();
    return p.equals(resolvedRoot, resolvedCandidate) ||
        p.isWithin(resolvedRoot, resolvedCandidate);
  } catch (_) {
    return false;
  }
}
