package Foo::Parent;

use Moose;
extends 'SimpleDB::Class::Domain';

__PACKAGE__->set_name('foo_parent');
__PACKAGE__->add_attributes(title=>{isa=>'Str'},domainids=>{isa=>'Str'});
__PACKAGE__->has_many('domains', 'Foo::Domain', 'parentId');
__PACKAGE__->has_indexed('indexed_domains', 'Foo::Domain', 'domainids');

1;

