print greet('Ingy', 42);

use Inline C => <<'END_OF_C_CODE';

void greet(char* name, int number) {
  Inline_Stack_Vars;
  int i;

  Inline_Stack_Reset;
  for (i = 0; i < number; i++)
    Inline_Stack_Push(sv_2mortal(newSVpvf("Hello %s!\n", name))); 

  Inline_Stack_Done;
}

END_OF_C_CODE
