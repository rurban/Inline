use Inline C => <<'END_OF_C_CODE';

void dump_hash(SV* hash_ref) {
  HV* hash;
  HE* hash_entry;
  int num_keys, i;
  SV* sv_key;
  SV* sv_val;

  if (! SvROK(hash_ref))
    croak("hash_ref is not a reference");

  hash = (HV*)SvRV(hash_ref);
  num_keys = hv_iterinit(hash);
  for (i = 0; i < num_keys; i++) {
    hash_entry = hv_iternext(hash);
    sv_key = hv_iterkeysv(hash_entry);
    sv_val = hv_iterval(hash, hash_entry);
    printf("%s => %s\n", SvPV(sv_key, PL_na), SvPV(sv_val, PL_na));
  }
  return;
}

END_OF_C_CODE

my %hash = (
	    Author => "Brian Ingerson",
	    Nickname => "INGY",
	    Module => "Inline.pm",
	    Version => "0.25",
	    Example => 7,
	   );

dump_hash(\%hash);
