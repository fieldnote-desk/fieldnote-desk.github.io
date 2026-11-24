import 'package:flutter/material.dart';
import 'platform.dart';

const _themePreference = 'fieldnote-palette-v2';
const _colorPreference = 'fieldnote-custom-color';

class Palette {
  const Palette(this.id, this.name, this.seed, {this.dark = false});
  final String id;
  final String name;
  final Color seed;
  final bool dark;
}

const palettes = [
  Palette('lime', '青柠绿', Color(0xff9bd553)),
  Palette('blue', '蓝色', Color(0xff5c97ee)),
  Palette('yellow', '黄色', Color(0xffecc957)),
  Palette('pink', '粉色', Color(0xffe78eb4)),
  Palette('orange', '橙色', Color(0xffee9a57)),
  Palette('purple', '紫色', Color(0xffa683d9)),
  Palette('neutral', '黑白', Color(0xff717680)),
];

Color? parseHex(String text) {
  final digits = text.trim().replaceFirst('#', '');
  if (!RegExp(r'^[\da-fA-F]{6}$').hasMatch(digits)) return null;
  return Color(0xff000000 | int.parse(digits, radix: 16));
}

String hexColor(Color color) =>
    '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0').toUpperCase()}';

Palette currentPalette() {
  final selected = readPreference(_themePreference);
  if (selected == 'custom') {
    final color = parseHex(readPreference(_colorPreference) ?? '');
    if (color != null) return Palette('custom', '自定义', color);
  }
  return palettes.firstWhere(
    (palette) => palette.id == selected,
    orElse: () => palettes.first,
  );
}

void rememberPalette(Palette palette) {
  if (palette.id == 'custom')
    writePreference(_colorPreference, hexColor(palette.seed));
  writePreference(_themePreference, palette.id);
}

ThemeData fieldnoteTheme(Palette palette) {
  final colors = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: palette.dark ? Brightness.dark : Brightness.light,
  );
  final colorScheme = colors.copyWith(
    surface: palette.dark ? const Color(0xff191820) : const Color(0xfffdfefb),
    onSurface: palette.dark ? const Color(0xfff3eff5) : const Color(0xff212723),
    surfaceContainerLowest: palette.dark
        ? const Color(0xff22212a)
        : Colors.white,
  );
  final paper = Color.alphaBlend(
    palette.seed.withValues(alpha: .075),
    const Color(0xfffcfcfa),
  );
  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: palette.dark ? const Color(0xff15141b) : paper,
    fontFamily: 'Fieldnote Sans',
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      isDense: true,
    ),
    dividerTheme: DividerThemeData(
      color: colorScheme.outlineVariant.withValues(alpha: .8),
    ),
  );
}

class PaletteRow extends StatelessWidget {
  const PaletteRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final Palette selected;
  final ValueChanged<Palette> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final palette in palettes)
          Tooltip(
            message: palette.name,
            child: Semantics(
              label: palette.name,
              selected: palette.id == selected.id,
              button: true,
              child: InkResponse(
                onTap: () => onChanged(palette),
                radius: 19,
                child: SizedBox(
                  width: 32,
                  height: 40,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: palette.id == selected.id ? 25 : 21,
                      height: palette.id == selected.id ? 25 : 21,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: palette.id == selected.id
                              ? colors.onSurface
                              : Colors.transparent,
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.seed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 5),
        IconButton(
          tooltip: '自定义颜色',
          onPressed: () async {
            final color = await showDialog<Color>(
              context: context,
              builder: (_) => _CustomColor(initial: selected.seed),
            );
            if (color != null) onChanged(Palette('custom', '自定义', color));
          },
          icon: selected.id == 'custom'
              ? Container(
                  width: 23,
                  height: 23,
                  decoration: BoxDecoration(
                    color: selected.seed,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.onSurface, width: 2),
                  ),
                )
              : const Icon(Icons.colorize_outlined, size: 20),
          color: colors.onSurface,
        ),
      ],
    );
  }
}

class _CustomColor extends StatefulWidget {
  const _CustomColor({required this.initial});
  final Color initial;

  @override
  State<_CustomColor> createState() => _CustomColorState();
}

class _CustomColorState extends State<_CustomColor> {
  late final TextEditingController text = TextEditingController(
    text: hexColor(widget.initial),
  );
  late HSVColor hsv = HSVColor.fromColor(widget.initial);

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  void change(HSVColor value) {
    setState(() {
      hsv = value;
      text.text = hexColor(hsv.toColor());
    });
  }

  Widget slider(
    String label,
    double value,
    double max,
    ValueChanged<double> onChange,
  ) {
    return Row(
      children: [
        SizedBox(width: 46, child: Text(label)),
        Expanded(
          child: Semantics(
            label: label,
            child: Slider(value: value, max: max, onChanged: onChange),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义颜色'),
      content: SizedBox(
        width: 370,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 58,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: hsv.toColor(),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            TextField(
              controller: text,
              decoration: InputDecoration(
                labelText: '十六进制颜色',
                hintText: '#B80023',
                errorText: parseHex(text.text) == null ? '请输入 6 位颜色代码' : null,
              ),
              onChanged: (value) => setState(() {
                final color = parseHex(value);
                if (color != null) hsv = HSVColor.fromColor(color);
              }),
            ),
            const SizedBox(height: 10),
            slider(
              '色相',
              hsv.hue,
              360,
              (value) => change(hsv.withHue(value.clamp(0, 359.99))),
            ),
            slider(
              '饱和',
              hsv.saturation,
              1,
              (value) => change(hsv.withSaturation(value)),
            ),
            slider('明度', hsv.value, 1, (value) => change(hsv.withValue(value))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: parseHex(text.text) == null
              ? null
              : () => Navigator.pop(context, hsv.toColor()),
          child: const Text('应用'),
        ),
      ],
    );
  }
}
