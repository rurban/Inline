greet('Ingy');
greet(42);

use Inline C => <<'END_OF_C_CODE';

void greet(char* name) {
  printf("Hello %s!\n", name);
}

END_OF_C_CODE
