import 'package:flutter/material.dart';

import 'net_image.dart';
import 'product_image.dart';
import 'tokens.dart';

/// The storefront kit: the pieces a marketplace home screen and store page are built from.
///
/// Everything here is presentational and takes plain values. None of it knows about the API, so the
/// same card renders a live store, a fixture in a widget test, and a shimmer placeholder.

// ---------------------------------------------------------------------------- status

/// Open / Busy / Closing soon / Closed.
class StoreStatePill extends StatelessWidget {
  const StoreStatePill({
    super.key,
    required this.state,
    required this.label,
    this.compact = false,
  });

  final DeliveryStoreState state;

  /// Already localised by the caller. The state carries the colour and nothing else, so the only
  /// way a pill can read English in an Arabic session is for the caller to hand it English.
  final String label;

  /// Drops the dot and tightens the padding, for overlaying on a cover image.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? DeliverySpacing.sm : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: state.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        border: Border.all(color: state.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (!compact) ...<Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: state.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: DeliverySpacing.xs + 2),
          ],
          Text(
            label,
            style: TextStyle(
              color: state.color,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rating and how many people gave it.
///
/// The count is not decoration: 4.8 from 12 people and 4.8 from 12,000 are different claims, and
/// showing the star alone flatters the first one.
class RatingChip extends StatelessWidget {
  const RatingChip({
    super.key,
    required this.rating,
    required this.unratedLabel,
    this.ratingCount = 0,
    this.dense = false,
  });

  final double? rating;

  /// What an unrated shop says instead of a score, already localised. The word used to be an
  /// English constant here, which is the same mistake the status pill made.
  final String unratedLabel;

  final int ratingCount;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final double? value = rating;
    if (value == null) {
      // Never render "0.0" for a shop nobody has rated — no data and a bad score must not look
      // the same.
      return Text(
        unratedLabel,
        style: TextStyle(
          color: DeliveryColors.muted,
          fontSize: dense ? 12 : 13,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, size: dense ? 14 : 16, color: const Color(0xFFF5A524)),
        const SizedBox(width: 2),
        Text(
          value.toStringAsFixed(1),
          style: TextStyle(
            color: DeliveryColors.ink,
            fontSize: dense ? 12 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (ratingCount > 0) ...<Widget>[
          const SizedBox(width: 3),
          Text(
            '(${_compactCount(ratingCount)})',
            style: TextStyle(color: DeliveryColors.muted, fontSize: dense ? 11 : 12),
          ),
        ],
      ],
    );
  }

  static String _compactCount(int count) {
    if (count >= 1000) {
      final double thousands = count / 1000;
      return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}k';
    }
    return '$count';
  }
}

/// A promotion flash.
class OfferBadge extends StatelessWidget {
  const OfferBadge({super.key, required this.label, this.icon = Icons.local_offer_rounded});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: DeliveryColors.brand,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: DeliveryColors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: DeliveryColors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------- imagery

/// The fallback when a store has no artwork.
///
/// A generated tile rather than a stock photo or a grey box: it is stable per store (the same shop
/// is always the same colour), it carries the brand, and it never claims to be a picture of
/// anything. The palette stays in the warm family so a grid of monograms reads as one brand rather
/// than a colour chart.
class StoreMonogram extends StatelessWidget {
  const StoreMonogram({super.key, required this.name, this.size, this.radius});

  final String name;
  final double? size;
  final double? radius;

  /// Six gradients spanning the rose family, the first matching the brand colour exactly.
  ///
  /// They stay deliberately distinguishable rather than collapsing to six shades of one rose: the
  /// point of a monogram is to tell two shops apart at a glance in a grid. All six are dark enough
  /// to carry the white initials on top.
  static const List<List<Color>> _palette = <List<Color>>[
    <Color>[Color(0xFFC41D4E), Color(0xFF8E1235)],
    <Color>[Color(0xFFE0466B), Color(0xFFA32448)],
    <Color>[Color(0xFFAD1457), Color(0xFF6A0B34)],
    <Color>[Color(0xFFD6455B), Color(0xFF9B2739)],
    <Color>[Color(0xFF9C1B5E), Color(0xFF5F0E39)],
    <Color>[Color(0xFFE0705E), Color(0xFF9C3C2F)],
  ];

  /// Deterministic on the name, so a store does not change colour between screens or reloads.
  List<Color> get _gradient {
    int hash = 0;
    for (final int unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  String get _initials {
    final List<String> words =
        name.trim().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      return '?';
    }
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return (words[0].characters.first + words[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final List<Color> colors = _gradient;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius ?? DeliveryRadius.md),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(DeliverySpacing.sm),
          child: Text(
            _initials,
            style: const TextStyle(
              color: DeliveryColors.white,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// A store's logo, falling back to its monogram.
class StoreAvatar extends StatelessWidget {
  const StoreAvatar({super.key, required this.name, this.logoUrl, this.size = 48});

  final String name;
  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? url = logoUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(DeliveryRadius.md),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? StoreMonogram(name: name, size: size)
            : Image(
                image: DeliveryImages.provider(url),
                fit: BoxFit.cover,
                errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                    StoreMonogram(name: name, size: size),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- layout

/// A titled section with an optional action on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          DeliverySpacing.md, DeliverySpacing.lg, DeliverySpacing.md, DeliverySpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: DeliveryColors.ink,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(fontSize: 13, color: DeliveryColors.muted),
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: DeliveryColors.brand,
                padding: const EdgeInsets.symmetric(horizontal: DeliverySpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// A horizontally scrolling row of selectable chips — the vertical switcher and the aisle switcher
/// are the same control with different contents.
/// How a [ChipStrip] arranges a chip's picture and its label.
enum ChipStripLayout {
  /// Label beside the glyph, in a bordered pill. Right for filters, where the chips are a row of
  /// competing options and the text is the thing being chosen.
  pill,

  /// Picture above, label beneath. Right for a category strip, where the picture is what the eye
  /// actually navigates by and the label only confirms it.
  stacked,
}

class ChipStrip<T> extends StatelessWidget {
  const ChipStrip({
    super.key,
    required this.values,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
    this.iconOf,
    this.imageOf,
    this.allLabel,
    this.layout = ChipStripLayout.pill,
    this.padding =
        const EdgeInsets.symmetric(horizontal: DeliverySpacing.md, vertical: DeliverySpacing.xs),
  });

  final List<T> values;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;

  /// An uploaded picture for the chip, taking precedence over [iconOf].
  ///
  /// A real photograph identifies a category far faster than a glyph does, and it is the thing a
  /// merchandiser can actually art-direct. The icon stays as the fallback for anything with no
  /// artwork yet, so the strip never renders a hole.
  final String? Function(T)? imageOf;
  final T? selected;

  /// Null means "the All chip was tapped".
  final ValueChanged<T?> onSelected;

  /// When set, a leading chip that clears the selection.
  final String? allLabel;
  final ChipStripLayout layout;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bool stacked = layout == ChipStripLayout.stacked;
    // Tall enough for the tallest chip rather than measured per item, so every tile in the strip
    // sits on the same baseline whether its label wraps to two lines or one.
    final double gap = stacked ? DeliverySpacing.xs : DeliverySpacing.sm;

    return SizedBox(
      height: stacked ? _stackedStripHeight + padding.vertical : 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        children: <Widget>[
          if (allLabel != null) ...<Widget>[
            _Chip(
              label: allLabel!,
              selected: selected == null,
              onTap: () => onSelected(null),
              layout: layout,
            ),
            SizedBox(width: gap),
          ],
          for (final T value in values) ...<Widget>[
            _Chip(
              label: labelOf(value),
              icon: iconOf?.call(value),
              imageUrl: imageOf?.call(value),
              selected: value == selected,
              onTap: () => onSelected(value),
              layout: layout,
            ),
            SizedBox(width: gap),
          ],
        ],
      ),
    );
  }
}

/// Diameter of the picture in a stacked chip, and the width of the column under it.
const double _stackedTile = 58;
const double _stackedWidth = 74;

/// Tile, gap, then two lines of label — the height every stacked chip reserves.
const double _stackedStripHeight = _stackedTile + 6 + 30;

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.imageUrl,
    this.layout = ChipStripLayout.pill,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final String? imageUrl;
  final ChipStripLayout layout;

  bool get _hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// The glyph shown when there is no artwork, or when the artwork fails to load.
  ///
  /// [onFill] is for the pill, whose selected state is a solid red fill. The stacked tile keeps a
  /// constant pale fill, so a white glyph there would disappear.
  Widget _fallbackIcon(double size, {bool onFill = true}) => Icon(
        icon ?? Icons.category_rounded,
        size: size,
        color: selected
            ? (onFill ? DeliveryColors.white : DeliveryColors.brand)
            : DeliveryColors.muted,
      );

  @override
  Widget build(BuildContext context) {
    return layout == ChipStripLayout.stacked ? _stacked() : _pill();
  }

  /// Picture above, label beneath, in a square tile.
  ///
  /// Square rather than round because a category picture is a photograph, and a circular mask
  /// crops the corners off every one of them. Selection is a border and red text rather than a
  /// filled shape: the picture is the point of this layout, and filling the tile would cover the
  /// very thing being selected.
  Widget _stacked() {
    final BorderRadius tileRadius = BorderRadius.circular(DeliveryRadius.md);
    return SizedBox(
      width: _stackedWidth,
      child: InkWell(
        onTap: onTap,
        borderRadius: tileRadius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Container(
              width: _stackedTile,
              height: _stackedTile,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: tileRadius,
                // The fill never changes with selection — only the border does. Category artwork
                // is transparent, so it sits directly on this tint; swapping the tint on select
                // would recolour the picture itself rather than mark it as chosen.
                color: DeliveryColors.brandSoft,
                border: Border.all(
                  color: selected ? DeliveryColors.brand : DeliveryColors.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: _hasImage
                  ? Image(
                      image: DeliveryImages.provider(imageUrl!),
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                          Center(child: _fallbackIcon(22, onFill: false)),
                    )
                  : Center(child: _fallbackIcon(24, onFill: false)),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? DeliveryColors.brand : DeliveryColors.ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 11.5,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill() {
    return Material(
      color: selected ? DeliveryColors.brand : DeliveryColors.white,
      borderRadius: BorderRadius.circular(DeliveryRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeliveryRadius.pill),
        child: Container(
          // Tighter when a picture sets the height. Keyed on the same test the content uses, so an
          // empty URL cannot give a chip the tall padding and the short icon.
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: _hasImage ? 6 : 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DeliveryRadius.pill),
            border: Border.all(
              color: selected ? DeliveryColors.brand : DeliveryColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Picture first, icon as the fallback. A failed load falls back too, rather than
              // leaving a broken frame in the middle of the strip.
              if (_hasImage) ...<Widget>[
                ClipOval(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: Image(
                      image: DeliveryImages.provider(imageUrl!),
                      fit: BoxFit.cover,
                      errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                          _fallbackIcon(15),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
              ] else if (icon != null) ...<Widget>[
                _fallbackIcon(15),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? DeliveryColors.white : DeliveryColors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- the card

/// The storefront card.
///
/// Deliberately dense. A marketplace card has to answer five questions at a glance — what is it,
/// is it any good, is it open, how long, what does delivery cost — and burying any of them behind a
/// tap is what makes a directory feel slow.
class StorefrontCard extends StatelessWidget {
  const StorefrontCard({
    super.key,
    required this.name,
    required this.state,
    required this.stateLabel,
    required this.unratedLabel,
    required this.etaLabel,
    required this.feeLabel,
    this.tagline,
    this.tags = const <String>[],
    this.rating,
    this.ratingCount = 0,
    this.coverUrl,
    this.logoUrl,
    this.offerLabel,
    this.favorite = false,
    this.onTap,
    this.onFavoriteToggled,
    this.favoriteLabel,
    this.unfavoriteLabel,
    this.coverHeight = 132,
  });

  final String name;
  final String? tagline;
  final List<String> tags;
  final DeliveryStoreState state;

  /// Already localised by the caller, like every other string this card is handed.
  final String stateLabel;

  /// What the rating slot says for a shop nobody has rated yet. Also already localised.
  final String unratedLabel;

  final String etaLabel;
  final String feeLabel;
  final double? rating;
  final int ratingCount;
  final String? coverUrl;
  final String? logoUrl;
  final String? offerLabel;
  final bool favorite;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggled;

  /// The heart's tooltip in each direction, already localised. Null leaves the button untooltipped
  /// rather than falling back to English — a missing hint is a smaller failure than a hint the
  /// reader cannot read.
  final String? favoriteLabel;
  final String? unfavoriteLabel;

  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    final bool shut = !state.acceptsOrders;

    return Material(
      color: DeliveryColors.white,
      borderRadius: BorderRadius.circular(DeliveryRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DeliveryRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DeliveryRadius.lg),
            // Lifted by a shadow rather than ringed by a border: a grid of bordered boxes reads as a
          // table, and this is meant to read as a shelf.
          boxShadow: DeliveryShadows.card,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _cover(shut),
              Padding(
                padding: const EdgeInsets.fromLTRB(DeliverySpacing.md, DeliverySpacing.sm + 2,
                    DeliverySpacing.md, DeliverySpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        // The merchant's own mark, beside the name rather than overlapping the
                        // cover. A shop is recognised by its logo long before its name is read,
                        // and in a filtered list — search results especially — the cover is often
                        // generic food photography while this is the thing that identifies who
                        // you are actually ordering from.
                        StoreAvatar(name: name, logoUrl: logoUrl, size: 40),
                        const SizedBox(width: DeliverySpacing.sm + 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: DeliveryColors.ink,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: DeliverySpacing.sm),
                                  RatingChip(
                                    rating: rating,
                                    ratingCount: ratingCount,
                                    unratedLabel: unratedLabel,
                                    dense: true,
                                  ),
                                ],
                              ),
                              if (tags.isNotEmpty || tagline != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    tags.isNotEmpty ? tags.join(' · ') : tagline!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12.5, color: DeliveryColors.muted),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                    Row(
                      children: <Widget>[
                        const Icon(Icons.schedule_rounded,
                            size: 14, color: DeliveryColors.muted),
                        const SizedBox(width: 4),
                        Text(etaLabel,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: DeliveryColors.ink,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(width: DeliverySpacing.md),
                        const Icon(Icons.delivery_dining_rounded,
                            size: 15, color: DeliveryColors.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            feeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: DeliveryColors.ink,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(bool shut) {
    final String? url = coverUrl;
    return SizedBox(
      height: coverHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (url == null || url.isEmpty)
            StoreMonogram(name: name, radius: 0)
          else
            Image(
              image: DeliveryImages.provider(url),
              fit: BoxFit.cover,
              errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
                  StoreMonogram(name: name, radius: 0),
            ),

          // A closed shop is dimmed rather than hidden. Customers look for a specific place and
          // need to be told it is shut, not left wondering why it vanished.
          if (shut)
            Container(color: Colors.black.withValues(alpha: 0.45)),

          Positioned(
            left: DeliverySpacing.sm,
            top: DeliverySpacing.sm,
            child: StoreStatePill(state: state, label: stateLabel, compact: true),
          ),
          if (offerLabel != null)
            Positioned(
              left: DeliverySpacing.sm,
              bottom: DeliverySpacing.sm,
              child: OfferBadge(label: offerLabel!),
            ),
          if (onFavoriteToggled != null)
            Positioned(
              right: DeliverySpacing.xs,
              top: DeliverySpacing.xs,
              child: Material(
                color: Colors.black.withValues(alpha: 0.35),
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: onFavoriteToggled,
                  visualDensity: VisualDensity.compact,
                  iconSize: 19,
                  tooltip: favorite ? unfavoriteLabel : favoriteLabel,
                  icon: Icon(
                    favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: favorite ? DeliveryColors.brand : DeliveryColors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The compact variant for a horizontal rail (favourites, "near you").
class StorefrontMiniCard extends StatelessWidget {
  const StorefrontMiniCard({
    super.key,
    required this.name,
    required this.state,
    required this.stateLabel,
    required this.unratedLabel,
    required this.etaLabel,
    this.logoUrl,
    this.rating,
    this.onTap,
    this.width = 148,
  });

  final String name;
  final DeliveryStoreState state;

  /// Already localised by the caller, like every other string this card is handed.
  final String stateLabel;

  /// What the rating slot says for a shop nobody has rated yet. Also already localised.
  final String unratedLabel;

  final String etaLabel;
  final String? logoUrl;
  final double? rating;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: DeliveryColors.white,
        borderRadius: BorderRadius.circular(DeliveryRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: Container(
            padding: const EdgeInsets.all(DeliverySpacing.sm + 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DeliveryRadius.md),
              // Lifted by a shadow rather than ringed by a border: a grid of bordered boxes reads as a
          // table, and this is meant to read as a shelf.
          boxShadow: DeliveryShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    StoreAvatar(name: name, logoUrl: logoUrl, size: 36),
                    const Spacer(),
                    StoreStatePill(state: state, label: stateLabel, compact: true),
                  ],
                ),
                const SizedBox(height: DeliverySpacing.sm),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: DeliveryColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    RatingChip(rating: rating, unratedLabel: unratedLabel, dense: true),
                    const Spacer(),
                    Text(etaLabel,
                        style: const TextStyle(fontSize: 11.5, color: DeliveryColors.muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- basket

/// The persistent basket bar.
///
/// Sits above the navigation bar rather than inside it, because the basket is the one thing a
/// customer must be able to reach from any tab without hunting for it.
class StickyBasketBar extends StatelessWidget {
  const StickyBasketBar({
    super.key,
    required this.itemCount,
    required this.total,
    required this.onTap,
    required this.label,
    this.blockedReason,
  });

  final int itemCount;
  final String total;
  final VoidCallback onTap;

  /// Already localised by the caller. This defaulted to "View basket" and the default is gone: a
  /// default is only ever taken when a caller forgot, which is precisely when English leaks.
  final String label;

  /// When set, the bar explains why checkout is unavailable instead of offering it — a minimum
  /// order not yet met, most often. It greys out and prints this in place of [label], and it STILL
  /// OPENS THE BASKET.
  ///
  /// It used to disable the bar outright. But the bar leads to the basket, not to checkout, and the
  /// basket is exactly where a customer under the minimum needs to be: it explains the shortfall in
  /// full, lets them change quantities, and has its own disabled checkout button. With the bar dead,
  /// a customer who had added products to a shop page's basket had no way to it from there — the
  /// Basket tab is under the pushed page — so "add 3.50 to reach the minimum" was a dead end rather
  /// than advice. Blocking checkout is the basket's job, not the way to it.
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final bool blocked = blockedReason != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            DeliverySpacing.md, 0, DeliverySpacing.md, DeliverySpacing.sm),
        child: Material(
          color: blocked ? DeliveryColors.muted : DeliveryColors.brand,
          borderRadius: BorderRadius.circular(DeliveryRadius.md),
          child: InkWell(
            // Live in both states — see [blockedReason].
            onTap: onTap,
            borderRadius: BorderRadius.circular(DeliveryRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: DeliverySpacing.md, vertical: DeliverySpacing.md - 2),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                    ),
                    child: Text('$itemCount',
                        style: const TextStyle(
                            color: DeliveryColors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                  const SizedBox(width: DeliverySpacing.sm + 2),
                  Expanded(
                    child: Text(
                      blockedReason ?? label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: DeliveryColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5),
                    ),
                  ),
                  Text(total,
                      style: const TextStyle(
                          color: DeliveryColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- product grid tile

/// A product as the dekkane shop's two-column grid draws it (Figma `customer-dekkane-shop`
/// 112:2041): a 100px picture, the name on one line, the dollar price over its LBP conversion, and
/// a full-width add button.
///
/// The frame draws only the empty state. Once the product is in the basket the button becomes a
/// stepper — the count, and the way back out — because a shelf you can only add to is a shelf you
/// have to leave to correct; [ShelfProductTile] made the same call.
///
/// Laid out top-and-bottom with the button pinned to the foot, so two tiles side by side in a
/// stretched row keep their buttons on one line whatever the names wrap to. In an unbounded column
/// it simply packs.
class ShelfGridTile extends StatelessWidget {
  const ShelfGridTile({
    super.key,
    required this.name,
    required this.price,
    required this.addLabel,
    this.secondaryPrice,
    this.imageUrl,
    this.quantityInBasket = 0,
    this.onAdd,
    this.onRemove,
    this.onTap,
    this.removeSemanticLabel,
    this.addMoreSemanticLabel,
  });

  final String name;

  /// The price as it should read, already formatted.
  final String price;

  /// The second figure under the price — the LBP conversion — or null to draw none. Null is the
  /// honest state when there is no rate: a price with an invented conversion is worse than one
  /// without.
  final String? secondaryPrice;

  final String? imageUrl;

  /// The add button's word, already localised.
  final String addLabel;

  final int quantityInBasket;

  /// Null draws no add control at all — a closed shop's shelf still browses, and a button that
  /// cannot add anything is not drawn. The space is kept so the grid does not jump.
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  /// Screen-reader labels for the stepper's two glyphs, localised by the caller.
  final String? removeSemanticLabel;
  final String? addMoreSemanticLabel;

  static const double imageHeight = 100;

  /// How tall the add button and the stepper are drawn: the frame's 32px.
  static const double controlHeight = 32;

  /// How tall a target they answer. A 32px control is under the 44–48px a thumb needs, so the 8px
  /// above and below the drawn control answer its tap too. That room is spacing the tile already
  /// had — the gap over the control and part of the bottom padding — moved inside the control's
  /// box, so the tile keeps its shape and nothing it draws moves.
  static const double hitHeight = 48;

  @override
  Widget build(BuildContext context) {
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DeliveryColors.white,
        borderRadius: corners,
        border: Border.all(color: DeliveryColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            // Short at the bottom by the part of [hitHeight] the control's box spans below it.
            padding: const EdgeInsetsDirectional.fromSTEB(
                DeliverySpacing.md - 4,
                DeliverySpacing.md - 4,
                DeliverySpacing.md - 4,
                DeliverySpacing.md - 4 - (hitHeight - controlHeight) / 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(DeliveryRadius.sm),
                      child: SizedBox(
                        height: imageHeight,
                        width: double.infinity,
                        child: DeliveryProductImage(url: imageUrl),
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.sm),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: DeliveryColors.brand,
                        height: 1.2,
                      ),
                    ),
                    if (secondaryPrice != null) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        secondaryPrice!,
                        style: const TextStyle(
                          fontSize: 10,
                          // Muted, not faint: faint is for decoration, and this is a price.
                          color: DeliveryColors.muted,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
                // No gap here: the 8px the tile used to leave above the control is the top of the
                // control's own tap area now ([hitHeight]).
                _control(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _control() {
    if (onAdd == null) {
      return const SizedBox(height: hitHeight);
    }
    final BorderRadius corners = BorderRadius.circular(DeliveryRadius.sm);
    if (quantityInBasket == 0) {
      // Drawn [controlHeight] tall, centred in a [hitHeight] box. A tap on the band above or below
      // reaches [onAdd] through the outer detector; one on the button itself through the InkWell,
      // whose ink stays inside the drawn button. Only the button is announced.
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onAdd,
        child: SizedBox(
          height: hitHeight,
          child: Center(
            child: Semantics(
              button: true,
              child: Material(
                color: DeliveryColors.brand,
                borderRadius: corners,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onAdd,
                  child: SizedBox(
                    height: controlHeight,
                    width: double.infinity,
                    child: Center(
                      child: Text(
                        addLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: DeliveryColors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: hitHeight,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: SizedBox(
              height: controlHeight,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(color: DeliveryColors.brand, borderRadius: corners),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              _step(Icons.remove_rounded, onRemove, removeSemanticLabel,
                  AlignmentDirectional.centerStart),
              Text(
                '$quantityInBasket',
                style: const TextStyle(
                    color: DeliveryColors.white, fontWeight: FontWeight.w800, fontSize: 13),
              ),
              _step(Icons.add_rounded, onAdd, addMoreSemanticLabel, AlignmentDirectional.centerEnd),
            ],
          ),
        ],
      ),
    );
  }

  /// One stepper glyph, drawn where the frame draws it — a 36px cell at the pill's end — but
  /// answering a [hitHeight]-square target that reaches over the band above and below the pill and
  /// 12px in towards the count. A GestureDetector rather than an InkWell: the old InkWell's ink was
  /// painted beneath the pill's own fill and never seen, and over the band it would be.
  Widget _step(IconData icon, VoidCallback? onTap, String? label, AlignmentGeometry end) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: hitHeight,
          height: hitHeight,
          child: Align(
            alignment: end,
            child: SizedBox(
              width: 36,
              height: controlHeight,
              child: Icon(icon, size: 17, color: DeliveryColors.white),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------- product row

/// A product as it appears on a store's shelf: text on the left, picture on the right, an add
/// control that shows quantity once there is one.
class ShelfProductTile extends StatelessWidget {
  const ShelfProductTile({
    super.key,
    required this.name,
    required this.price,
    this.description,
    this.imageUrl,
    this.quantityInBasket = 0,
    this.onAdd,
    this.onRemove,
    this.onTap,
    this.enabled = true,
  });

  final String name;
  final String price;
  final String? description;
  final String? imageUrl;
  final int quantityInBasket;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: DeliverySpacing.md, vertical: DeliverySpacing.sm + 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: DeliveryColors.ink,
                        height: 1.25,
                      ),
                    ),
                    if (description != null && description!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: DeliveryColors.muted, height: 1.3),
                      ),
                    ],
                    const SizedBox(height: DeliverySpacing.sm),
                    Text(
                      price,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: DeliveryColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DeliverySpacing.md),
              SizedBox(
                width: 92,
                child: Column(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(DeliveryRadius.md),
                      child: SizedBox(
                        height: 78,
                        width: 92,
                        child: DeliveryProductImage(url: imageUrl),
                      ),
                    ),
                    const SizedBox(height: DeliverySpacing.xs),
                    _quantityControl(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quantityControl() {
    if (!enabled) {
      return const SizedBox(height: 32);
    }
    if (quantityInBasket == 0) {
      return SizedBox(
        height: 32,
        width: 92,
        child: OutlinedButton(
          onPressed: onAdd,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            foregroundColor: DeliveryColors.brand,
            side: const BorderSide(color: DeliveryColors.brandLine),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DeliveryRadius.sm)),
          ),
          child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      );
    }
    return Container(
      height: 32,
      width: 92,
      decoration: BoxDecoration(
        color: DeliveryColors.brand,
        borderRadius: BorderRadius.circular(DeliveryRadius.sm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _stepper(Icons.remove_rounded, onRemove),
          Text('$quantityInBasket',
              style: const TextStyle(
                  color: DeliveryColors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          _stepper(Icons.add_rounded, onAdd),
        ],
      ),
    );
  }

  Widget _stepper(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 30,
        height: 32,
        child: Icon(icon, size: 17, color: DeliveryColors.white),
      ),
    );
  }
}
