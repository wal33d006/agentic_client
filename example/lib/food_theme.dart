import 'package:flutter/material.dart';

/// Shared warm, food-friendly styling for the ordering widgets
/// (RestaurantList, RestaurantMenu and the CartSummary checkout).
///
/// Colors are baked in (rather than read from the app `ColorScheme`) so the
/// surfaces look appetizing regardless of the host app's seed color.
class FoodTheme {
  FoodTheme._();

  static const Color brand = Color(0xFFF4511E); // deep orange
  static const Color brandDeep = Color(0xFFD84315);
  static const Color amber = Color(0xFFFFB300);

  /// Warm "appetite" gradient used on headers and primary buttons.
  static const List<Color> appetiteGradient = [Color(0xFFFF6A3D), Color(0xFFF9A826)];

  /// Celebratory green gradient for the paid/confirmation state.
  static const List<Color> successGradient = [Color(0xFF2E9E5B), Color(0xFF66BB6A)];

  static const Color ink = Color(0xFF2B2118); // warm near-black for text
  static const Color inkSoft = Color(0xFF8A7E74); // muted warm grey
  static const Color hairline = Color(0xFFF0E7E0); // soft divider
  static const Color avatarBg = Color(0xFFFFF1EA); // soft peach tint
  static const Color brandShadow = Color(0x2EF4511E); // ~18% brand
  static const Color ratingBg = Color(0xFFFFF3E0);
  static const Color ratingFg = Color(0xFFEF6C00);
}

/// A rounded, softly-shadowed card that wraps each ordering surface.
class FoodCard extends StatelessWidget {
  const FoodCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: FoodTheme.brandShadow, blurRadius: 30, spreadRadius: -6, offset: Offset(0, 12)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A gradient header bar with an optional back button, emoji, title/subtitle
/// and a "step N of M" pill.
class FoodHeader extends StatelessWidget {
  const FoodHeader({
    super.key,
    required this.title,
    this.emoji,
    this.subtitle,
    this.step,
    this.onBack,
    this.gradient = FoodTheme.appetiteGradient,
  });

  final String title;
  final String? emoji;
  final String? subtitle;
  final String? step;
  final VoidCallback? onBack;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.fromLTRB(onBack != null ? 6 : 18, 16, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
            ),
          if (emoji != null) ...[
            Text(emoji!, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (step != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
              child: Text(
                step!,
                style: textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A rounded, tinted square holding a food emoji.
class EmojiAvatar extends StatelessWidget {
  const EmojiAvatar({super.key, required this.emoji, this.size = 44, this.background = FoodTheme.avatarBg});

  final String emoji;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.5)),
    );
  }
}

/// Maps a dish/product name to a representative emoji (keyword based, with a
/// sensible fallback). Covers the food menu plus the simple-cart demo items.
String foodEmoji(String name) {
  final n = name.toLowerCase();
  bool has(List<String> keys) => keys.any(n.contains);

  if (has(['cheeseburger', 'burger'])) return '🍔';
  if (has(['fries', 'fry'])) return '🍟';
  if (has(['milkshake', 'shake', 'smoothie'])) return '🥤';
  if (has(['nigiri', 'sashimi', 'sushi'])) return '🍣';
  if (has(['roll', 'maki'])) return '🍙';
  if (has(['miso', 'ramen', 'soup', 'pho'])) return '🍜';
  if (has(['carbonara', 'spaghetti', 'pasta', 'noodle'])) return '🍝';
  if (has(['pizza'])) return '🍕';
  if (has(['garlic bread', 'bread', 'baguette', 'toast'])) return '🥖';
  if (has(['tiramisu', 'cake', 'dessert', 'tart'])) return '🍰';
  if (has(['ice cream', 'gelato'])) return '🍨';
  if (has(['salad'])) return '🥗';
  if (has(['chicken', 'wing'])) return '🍗';
  if (has(['taco', 'burrito'])) return '🌮';
  if (has(['coffee', 'mug', 'latte', 'espresso'])) return '☕';
  if (has(['tea', 'matcha'])) return '🍵';
  if (has(['water', 'bottle', 'juice', 'drink', 'soda'])) return '🥤';
  if (has(['notebook', 'book', 'paper', 'journal'])) return '📓';
  if (has(['headphone', 'audio', 'music'])) return '🎧';
  return '🍽️';
}

/// Picks an emoji for a restaurant from its cuisine (or name) string.
String cuisineEmoji(String cuisine) {
  final n = cuisine.toLowerCase();
  bool has(List<String> keys) => keys.any(n.contains);

  if (has(['sushi', 'japanese', 'ramen'])) return '🍣';
  if (has(['burger', 'american', 'grill'])) return '🍔';
  if (has(['pasta', 'italian', 'pizza'])) return '🍝';
  if (has(['mexican', 'taco', 'burrito'])) return '🌮';
  if (has(['indian', 'curry'])) return '🍛';
  if (has(['chinese', 'thai', 'noodle', 'asian'])) return '🥡';
  if (has(['coffee', 'cafe', 'bakery', 'dessert'])) return '🧁';
  return '🍴';
}

/// A small amber rating chip, e.g. ⭐ 4.5.
class RatingPill extends StatelessWidget {
  const RatingPill({super.key, required this.rating});

  final String rating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: FoodTheme.ratingBg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 15, color: FoodTheme.ratingFg),
          const SizedBox(width: 2),
          Text(
            rating,
            style: const TextStyle(color: FoodTheme.ratingFg, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// A full-width pill button with the warm appetite gradient.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.gradient = FoodTheme.appetiteGradient,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final List<Color> gradient;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? LinearGradient(colors: gradient) : null,
        color: enabled ? null : const Color(0xFFE6DED7),
        borderRadius: BorderRadius.circular(30),
        boxShadow: enabled
            ? const [BoxShadow(color: FoodTheme.brandShadow, blurRadius: 14, offset: Offset(0, 6))]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: enabled ? Colors.white : FoodTheme.inkSoft),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? Colors.white : FoodTheme.inkSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
