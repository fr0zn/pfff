void main () {
  int y = 10;
  int* x = malloc(y * sizeof(int));
  int w = x[y];

  int z = 2;
  x[y] = z;

  int *elt;
  elt = &x[y];
}
