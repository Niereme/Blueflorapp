import 'package:blueflora/data/local_tree_repository.dart';
import 'package:blueflora/application/trees_controller.dart';
import 'package:blueflora/domain/tree.dart';
import 'package:blueflora/presentation/screens/views/addtree_view.dart';
import 'tree_detail_view.dart';
import 'package:blueflora/presentation/squares/tree_square.dart';
import 'package:flutter/material.dart';
import 'package:blueflora/presentation/design/blueflora_theme.dart';
import 'package:blueflora/presentation/design/flora_components.dart';

class TreesView extends StatefulWidget {
  const TreesView({super.key, this.controller, this.repository})
    : assert(controller != null || repository != null),
      assert(controller == null || repository == null);

  final LocalTreeRepository? repository;
  final TreesController? controller;

  @override
  State<TreesView> createState() => _TreesViewState();
}

class _TreesViewState extends State<TreesView> {
  late final TreesController _controller;
  late final bool _ownsController;
  bool _adding = false;

  List<Tree> get _trees => _controller.trees;
  bool get _loading => _controller.loading;
  bool get _saving => _controller.saving;
  String? get _loadError => _controller.loadError;
  String? get _saveError => _controller.saveError;
  bool get _canModify => _controller.canModify && !_adding;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? TreesController(repository: widget.repository!);
    if (_ownsController) _controller.load();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  Future<void> _addTree() => _openForm();

  Future<void> _openForm([Tree? tree]) async {
    if (!_canModify) return;
    setState(() => _adding = true);
    final result = await Navigator.push<Tree>(
      context,
      MaterialPageRoute(builder: (context) => AddTreeView(tree: tree)),
    );
    if (!mounted) return;
    setState(() => _adding = false);
    if (result != null) {
      if (tree == null) {
        await _controller.add(result);
      } else {
        await _controller.edit(result);
      }
    }
  }

  Future<bool> _confirmDelete(Tree tree) async {
    if (!_canModify) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar árbol'),
        content: const Text('¿Seguro que quieres eliminar este árbol?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || !_canModify) return false;
    await _controller.delete(tree.id);
    // La lista se actualiza tras guardar. No se inicia una animación que pueda
    // dejar un Dismissible eliminado en pantalla si la escritura falla.
    return false;
  }

  Widget _buildBody() {
    final colors = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 96),
      itemCount: (_loading || _loadError != null) ? 1 : _trees.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saving) const FloraLoading(label: 'Guardando cambios…'),
              if (_saveError != null)
                FloraMessage(
                  title: 'Los cambios siguen pendientes',
                  message: _saveError!,
                  status: FloraStatus.error,
                  action: TextButton(
                    onPressed: _canModify && _controller.canRetrySave
                        ? _controller.retrySave
                        : null,
                    child: const Text('Reintentar guardado'),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: FloraTokens.padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FloraSectionHeading(title: 'Mis árboles'),
                    Text('Pequeños cuidados, un jardín que crece contigo.'),
                  ],
                ),
              ),
              if (_loading)
                FloraInfoCard(
                  child: Column(
                    children: [
                      if (MediaQuery.disableAnimationsOf(context))
                        const Icon(Icons.hourglass_empty)
                      else
                        const CircularProgressIndicator(),
                      const SizedBox(height: FloraTokens.padding),
                      const Text('Preparando tus plantas…'),
                    ],
                  ),
                )
              else if (_loadError != null)
                FloraMessage(
                  title: 'No pudimos abrir tu jardín',
                  message: _loadError!,
                  status: FloraStatus.error,
                  action: TextButton(
                    onPressed: _controller.load,
                    child: const Text('Reintentar'),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.all(FloraTokens.padding),
                  child: Text(
                    '${_trees.length} ${_trees.length == 1 ? 'planta registrada' : 'plantas registradas'}',
                    key: const ValueKey('trees-total'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_trees.isEmpty)
                  FloraMessage(
                    title: 'Aquí empieza tu jardín',
                    message:
                        'Agrega tu primera planta y organiza sus cuidados a tu ritmo.',
                    action: FilledButton.icon(
                      onPressed: _canModify ? _addTree : null,
                      icon: const Icon(Icons.eco_outlined),
                      label: const Text('Agregar primera planta'),
                    ),
                  ),
              ],
            ],
          );
        }
        final tree = _trees[index - 1];
        return Dismissible(
          key: ValueKey(tree.id),
          direction: _canModify
              ? DismissDirection.endToStart
              : DismissDirection.none,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.all(FloraTokens.padding),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(FloraTokens.radius),
            ),
            child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
          ),
          confirmDismiss: (_) => _confirmDelete(tree),
          child: TreeSquare(
            tree: tree,
            now: _controller.now,
            enabled: _canModify,
            onEdit: () => _openForm(tree),
            onDelete: () => _confirmDelete(tree),
            onOpen: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TreeDetailView(controller: _controller, plantId: tree.id),
              ),
            ),
            onWater: () {
              if (!_canModify) return;
              _controller.water(tree.id);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, child) => Scaffold(
      appBar: AppBar(title: const Text('Árboles')),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _canModify ? _addTree : null,
        tooltip: 'Agregar planta',
        child: const Icon(Icons.add),
      ),
    ),
  );
}
