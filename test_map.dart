void main() {
  String? value = 'hello';
  String? nullValue = null;
  var map = {
    'k1': ?value,
    'k2': ?nullValue,
  };
  print(map);
}
