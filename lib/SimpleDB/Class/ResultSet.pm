package SimpleDB::Class::ResultSet;

=head1 NAME

SimpleDB::Class::ResultSet - An iterator of items from a domain.

=head1 DESCRIPTION

This class is an iterator to walk to the items passed back from a query. 

B<Warning:> Once you have a result set and you start calling methods on it, it will begin iterating over the result set. Therefore you can't call both C<next> and C<search>, or any other combinations of methods on an existing result set.

B<Warning:> If you call a method like C<search> on a result set which causes another query to be run, know that the original result set must be very small. This is because there is a limit of 20 comparisons per request as a limitation of SimpleDB.

=head1 METHODS

The following methods are available from this class.

=cut

use Moose;
use SimpleDB::Class::SQL;

#--------------------------------------------------------

=head2 new ( params )

Constructor.

=head3 params

A hash.

=head4 simpledb

Required. A L<SimpleDB::Class> object.

=head4 item_class

Required. A L<SimpleDB::Class::Item> subclass name.

=head4 result

A result as returned from the send_request() method from L<SimpleDB::Class::HTTP>. Either this or a where is required.

=head4 where

A where clause as defined in L<SimpleDB::Class::SQL>. Either this or a result is required.

=head4 order_by

An order_by clause as defined in L<SimpleDB::Class::SQL>. Optional.

=head4 limit

A limit clause as defined in L<SimpleDB::Class::SQL>. Optional.

=head4 consistent

A boolean that if set true will get around Eventual Consistency, but at a reduced performance. Optional.

=head4 set

A hash reference of attribute names and values, which will be set on the item as C<next> is called. Doing so helps to prevent stale object references.

=cut

#--------------------------------------------------------

=head2 item_class ( )

Returns the item_class passed into the constructor.

=cut

has item_class => (
    is          => 'ro',
    isa         => 'ClassName',
    required    => 1,
);

with 'SimpleDB::Class::Role::Itemized';

#--------------------------------------------------------

=head2 consistent ( )

Returns the consistent value passed into the constructor.

=cut

has consistent => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

#--------------------------------------------------------

=head2 set ( )

Returns the set value passed into the constructor.

=cut

has set => (
    is      => 'ro',
    isa         => 'HashRef',
    default => sub { {} },
);

#--------------------------------------------------------

=head2 where ( )

Returns the where passed into the constructor.

=cut

has where => (
    is          => 'ro',
    isa         => 'HashRef',
);

#--------------------------------------------------------

=head2 order_by ( )

Returns the order_by passed into the constructor.

=cut

has order_by => (
    is          => 'ro',
    isa         => 'Str | ArrayRef[Str]',
    predicate   => 'has_order_by',
);

#--------------------------------------------------------

=head2 limit ( )

Returns the limit passed into the constructor.

=cut

has limit => (
    is          => 'rw',
    isa         => 'Str',
    predicate   => 'has_limit',
);

#--------------------------------------------------------

=head2 simpledb ( )

Returns the simpledb passed into the constructor.

=cut

has simpledb => (
    is          => 'ro',
    required    => 1,
);

#--------------------------------------------------------

=head2 result ( )

Returns the result passed into the constructor, or the one generated by fetch_result() if a where is passed into the constructor.

=head2 has_result () 

A boolean indicating whether a result was passed into the constructor, or generated by fetch_result().

=cut

has result => (
    is          => 'rw',
    isa         => 'HashRef',
    predicate   => 'has_result',
    default     => sub {{}},
    lazy        => 1,
);

#--------------------------------------------------------

=head2 iterator ( )

Returns an integer which represents the current position in the result set as traversed by next().

=cut

has iterator => (
    is          => 'rw',
    isa         => 'Int',
    default     => 0,
);


#--------------------------------------------------------

=head2 fetch_result ( [ next ] )

Fetches a result, based on a where clause passed into a constructor, and then makes it accessible via the result() method.

=head3 next

A next token, in order to fetch the next part of a result set.

=cut

sub fetch_result {
    my ($self, $next) = @_;
    my %sql_params = (
        item_class  => $self->item_class,
        simpledb    => $self->simpledb,
        where       => $self->where,
        );
    if ($self->has_order_by) {
        $sql_params{order_by} = $self->order_by;
    }
    if ($self->has_limit) {
        $sql_params{limit} = $self->limit;
    }
    my $select = SimpleDB::Class::SQL->new(%sql_params);
    my %params = (SelectExpression => $select->to_sql);
    if ($self->consistent) {
        $params{ConsistentRead} = 'true';
    }

    # if we're fetching and we already have a result, we can assume we're getting the next batch
    if (defined $next && $next ne '') { 
        $params{NextToken} = $next;
    }

    my $result = $self->simpledb->http->send_request('Select', \%params);
    $self->result($result);
    return $result;
}

#--------------------------------------------------------

=head2 count (  [ options ]  )

Counts the items in the result set. Returns an integer. 

=head3 options

A hash of extra options you can pass to modify the count.

=head4 where

A where clause as defined by L<SimpleDB::Class::SQL>. If this is specified, then an additional query is executed before counting the items in the result set.

=cut

sub count {
    my ($self, %options) = @_;
    my @ids;
    while (my $item = $self->next) {
        push @ids, $item->id;
    }
    if ($options{where}) {
        my $clauses = { 
            'itemName()'    => ['in',@ids], 
            '-and'          => $options{where},
        };
        my $select = SimpleDB::Class::SQL->new(
            item_class  => $self->item_class,
            simpledb    => $self->simpledb,
            where       => $clauses,
            output      => 'count(*)',
        );
        my %params = ( SelectExpression    => $select->to_sql );
        if ($self->consistent) {
            $params{ConsistentRead} = 'true';
        }
        my $result = $self->simpledb->http->send_request('Select', \%params);
        return $result->{SelectResult}{Item}[0]{Attribute}{Value};
    }
    else {
        return scalar @ids;
    }
}

#--------------------------------------------------------

=head2 search ( options )

Just like L<SimpleDB::Class::Domain/"search">, but searches within the confines of the current result set, and then returns a new result set.

=head3 options

A hash of extra options to modify the search.

=head4 where

A where clause as defined by L<SimpleDB::Class::SQL>.

=cut

sub search {
    my ($self, %options) = @_;
    my @ids;
    while (my $item = $self->next) {
        push @ids, $item->id;
    }
    my $clauses = { 
        'itemName()'      => ['in',@ids], 
        '-and'  => $options{where},
    };
    return $self->new(
        simpledb    => $self->simpledb,
        item_class  => $self->item_class,
        where       => $clauses,
        consistent  => $self->consistent,
        set         => $self->set,
        );
}

#--------------------------------------------------------

=head2 update ( attributes )

Calls C<update> and then C<put> on all the items in the result set. 

=head3 attributes

A hash reference containing name/value pairs to update in each item.

=cut

sub update {
    my ($self, $attributes) = @_;
    while (my $item = $self->next) {
        $item->update($attributes)->put;
    }
}

#--------------------------------------------------------

=head2 delete ( )

Calls C<delete> on all the items in the result set.

=cut

sub delete {
    my ($self) = @_;
    while (my $item = $self->next) {
        $item->delete;
    }
}

#--------------------------------------------------------

=head2 paginate ( items_per_page, page_number ) 

Use on a new result set to fast forward to the desired data. After you've paginated, you can call C<next> to start fetching your data. Returns a reference to the result set for easy method chaining.

B<NOTE:> Unless you've already set a limit, the limit for this result set will be set to C<items_per_page> as a convenience. 

=head3 items_per_page

An integer representing how many items you're fetching/displaying per page.

=head3 page_number

An integer representing what page number you'd like to skip ahead to.

=cut

sub paginate {
    my ($self, $items_per_page, $page_number) = @_;
    unless ($self->has_limit) {
        $self->limit($items_per_page);
    }
    my $limit = ($items_per_page * ($page_number - 1));
    return $self if $limit == 0;
    my %sql_params = (
        item_class  => $self->item_class,
        simpledb    => $self->simpledb,
        where       => $self->where,
        output      => 'count(*)',
        limit       => $limit,
        );
    if ($self->has_order_by) {
        $sql_params{order_by} = $self->order_by;
    }
    my $select = SimpleDB::Class::SQL->new(%sql_params);
    my %params = (SelectExpression => $select->to_sql);
    if ($self->consistent) {
        $params{ConsistentRead} = 'true';
    }
    my $result = $self->simpledb->http->send_request('Select', \%params);
    $self->fetch_result($result->{SelectResult}{NextToken});
    return $self;
}


#--------------------------------------------------------

=head2 next () 

Returns the next result in the result set. Also fetches th next partial result set if there's a next token in the first result set and you've iterated through the first partial set.

=cut

sub next {
    my ($self) = @_;
    # get the current results
    my $result = ($self->has_result) ? $self->result : $self->fetch_result;
    my $items = [];
    if (ref $result->{SelectResult}{Item} eq 'ARRAY') {
        $items = $result->{SelectResult}{Item};
    }

    # fetch more results if needed
    my $iterator = $self->iterator;
    if ($iterator >= scalar @{$items}) {
        if (exists $result->{SelectResult}{NextToken}) {
            $self->iterator(0);
            $iterator = 0;
            $result = $self->fetch_result($result->{SelectResult}{NextToken});
            $items = $result->{SelectResult}{Item};
        }
        else {
            return undef;
        }
    }

    # iterate
    my $item = $items->[$iterator];
    return undef unless defined $item;
    $iterator++;
    $self->iterator($iterator);

    # make the item object
    my $db = $self->simpledb;
    my $domain_name = $db->add_domain_prefix($self->item_class->domain_name);
    my $cache = $db->cache;
    ## fetch from cache even though we've already pulled it back from the db, because the one in cache
    ## might be more up to date than the one from the DB
    my $attributes = eval{$cache->get($domain_name, $item->{Name})}; 
    my $e;
    my $itemobj;
    if ($e = SimpleDB::Class::Exception::ObjectNotFound->caught) {
        $itemobj = $self->parse_item($item->{Name}, $item->{Attribute});
        if (defined $itemobj) {
            eval{$cache->set($domain_name, $item->{Name}, $itemobj->to_hashref)};
        }
    }
    elsif ($e = SimpleDB::Class::Exception->caught) {
        warn $e->error;
        $e->rethrow;
    }
    elsif (defined $attributes) {
        $itemobj = $self->instantiate_item($attributes,$item->{Name});
    }
    else {
        SimpleDB::Class::Exception->throw(error=>"An undefined error occured while fetching the item from cache.");
    }

    # process the 'set' option
    my %set = %{$self->set};
    foreach my $attribute (keys %set) {
        $itemobj->$attribute( $set{$attribute} );
    }

    return $itemobj;
}

#--------------------------------------------------------

=head2 to_array_ref ()

Returns an array reference containing all the objects in the result set. If the result set has already been partially walked, then only the remaining objects will be returned.

=cut

sub to_array_ref {
    my ($self) = @_;
    my @all;
    while (my $object = $self->next) {
        push @all, $object;
    }
    return \@all;
}


=head1 LEGAL

SimpleDB::Class is Copyright 2009-2010 Plain Black Corporation (L<http://www.plainblack.com/>) and is licensed under the same terms as Perl itself.

=cut

no Moose;
__PACKAGE__->meta->make_immutable;
