import 'package:flutter/material.dart';

import 'store_models.dart';

/// The glyph for each service category.
///
/// Here rather than in an app, because the provider's screens (delivery_merchant) and the
/// customer's Services tab (mobile_app) both draw categories, and must not draw one differently.
///
/// The Services frames draw Tailoring as a circle with a cross, which reads as "close" or "error",
/// so Tailoring gets scissors. Outlined glyphs, to match the frames' line icons.
extension ServiceCategoryIcon on ServiceCategory {
  IconData get icon => switch (this) {
        ServiceCategory.printing => Icons.print_outlined,
        ServiceCategory.tailoring => Icons.content_cut_rounded,
        ServiceCategory.repairs => Icons.build_outlined,
        ServiceCategory.photography => Icons.photo_camera_outlined,
        ServiceCategory.cleaning => Icons.cleaning_services_outlined,
        ServiceCategory.beauty => Icons.auto_awesome_outlined,
        ServiceCategory.tutoring => Icons.menu_book_outlined,
      };
}
