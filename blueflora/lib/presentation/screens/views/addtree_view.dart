import 'package:blueflora/domain/tree.dart';
import 'package:flutter/material.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';

/// Formulario compartido para registrar y editar una planta.
class AddTreeView extends StatefulWidget {
  const AddTreeView({super.key, this.tree});

  final Tree? tree;

  @override
  State<AddTreeView> createState() => _AddTreeViewState();
}

class _AddTreeViewState extends State<AddTreeView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController nombreController;
  late final TextEditingController especieController;
  late final TextEditingController alturaController;
  late final TextEditingController riegoController;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final tree = widget.tree;
    nombreController = TextEditingController(text: tree?.nombre ?? '');
    especieController = TextEditingController(text: tree?.especie ?? '');
    alturaController = TextEditingController(
      text: tree?.altura?.toString() ?? '',
    );
    riegoController = TextEditingController(
      text: tree?.frecuenciaRiegoDias.toString() ?? '',
    );
  }

  @override
  void dispose() {
    nombreController.dispose();
    especieController.dispose();
    alturaController.dispose();
    riegoController.dispose();
    super.dispose();
  }

  double? _parseAltura(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.'));

  void _submit() {
    if (_submitted || !_formKey.currentState!.validate()) return;
    final nombre = nombreController.text.trim();
    final especie = especieController.text.trim();
    final altura = alturaController.text.trim().isEmpty
        ? null
        : _parseAltura(alturaController.text);
    final dias = Tree.parseFrecuenciaDias(riegoController.text)!;
    final tree = widget.tree;
    final result = tree == null
        ? Tree(
            nombre: nombre,
            especie: especie.isEmpty ? null : especie,
            altura: altura,
            frecuenciaRiegoDias: dias,
            // Se conserva el comportamiento de registro existente.
            ultimoRiego: DateTime.now(),
          )
        : tree.copyWith(
            nombre: nombre,
            especie: especie.isEmpty ? null : especie,
            altura: altura,
            frecuenciaRiegoDias: dias,
          );
    _submitted = true;
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.tree == null ? 'Agregar árbol' : 'Editar árbol'),
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FloraTokens.padding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FloraInfoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.eco_outlined,
                      color: Theme.of(context).colorScheme.primary,
                      size: 32,
                    ),
                    FloraSectionHeading(
                      title: widget.tree == null
                          ? 'Un nuevo rincón verde'
                          : 'Los detalles de tu planta',
                    ),
                    const Text(
                      'Completa los campos obligatorios. Especie y altura son opcionales.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FloraTokens.padding),
              TextFormField(
                controller: nombreController,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre del árbol',
                  helperText: 'Obligatorio. ¿Cómo llamas a tu planta?',
                  prefixIcon: Icon(Icons.park_outlined),
                  errorMaxLines: 4,
                  helperMaxLines: 4,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe el nombre de tu planta.'
                    : null,
              ),
              const SizedBox(height: FloraTokens.section),
              TextFormField(
                controller: especieController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Especie (opcional)',
                  prefixIcon: Icon(Icons.eco_outlined),
                  errorMaxLines: 4,
                  helperMaxLines: 4,
                ),
              ),
              const SizedBox(height: FloraTokens.section),
              TextFormField(
                controller: alturaController,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Altura en metros (opcional)',
                  helperText: 'Por ejemplo, 1,5. Puedes dejarla vacía.',
                  prefixIcon: Icon(Icons.straighten_outlined),
                  errorMaxLines: 4,
                  helperMaxLines: 4,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final height = _parseAltura(value);
                  return height == null || !height.isFinite || height <= 0
                      ? 'Escribe una altura positiva, por ejemplo 1,5.'
                      : null;
                },
              ),
              const SizedBox(height: FloraTokens.section),
              TextFormField(
                controller: riegoController,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Frecuencia de riego (días)',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                  helperText:
                      'Obligatoria. Días enteros: 7 equivale a una semana.',
                  errorMaxLines: 4,
                  helperMaxLines: 4,
                ),
                validator: (value) =>
                    Tree.parseFrecuenciaDias(value ?? '') == null
                    ? 'Escribe días enteros entre 1 y ${Tree.maxFrecuenciaDias}.'
                    : null,
              ),
              const SizedBox(height: FloraTokens.section),
              ElevatedButton(
                onPressed: _submit,
                child: Text(
                  widget.tree == null ? 'Guardar árbol' : 'Guardar cambios',
                ),
              ),
              const SizedBox(height: FloraTokens.space),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
