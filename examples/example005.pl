greet(qw(Brian Ingerson Ingy Me Myself I));

use Inline C => <<'END_OF_C_CODE';

void greet(SV* name1, ...) {
  dXSARGS;
  int i;

  for (i = 0; i < items; i++) 
    printf("Hello %s!\n", SvPV(ST(i), PL_na));
}

END_OF_C_CODE

__END__
