/// An operario (field worker) supervised by the logged-in supervisor.
class Operario {
  const Operario({
    required this.id,
    required this.fullName,
    required this.documento,
    required this.active,
  });

  final String id;
  final String fullName;
  final String documento;
  final bool active;
}
