void main() {
  String? value = 'test';
  var map = {'k1': ?value};
  print(map['k1']);
  print(map.containsKey('k1'));
}
