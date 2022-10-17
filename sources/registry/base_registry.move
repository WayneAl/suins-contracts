module suins::base_registry {
    use sui::event;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::vec_map::{Self, VecMap};
    use sui::vec_set::{Self, VecSet};
    use std::option::{Self, Option};
    use std::string::{Self, String};

    friend suins::sui_registrar;
    friend suins::reverse_registrar;
    friend suins::sui_controller;

    const MOVE_BASE_NODE: vector<u8> = b"move";
    const SUI_BASE_NODE: vector<u8> = b"sui";
    const ADDR_REVERSE_BASE_NODE: vector<u8> = b"addr.reverse";
    const MAX_TTL: u64 = 0x100000;

    // errors in the range of 101..200 indicate Registry errors
    const EUnauthorized: u64 = 101;
    const ERecordNotExists: u64 = 102;

    // https://examples.sui.io/patterns/capability.html
    struct AdminCap has key { id: UID }

    struct NewOwnerEvent has copy, drop {
        node: String,
        owner: address,
    }

    struct NewSubnodeOwnerEvent has copy, drop {
        base_node: String,
        label: String,
        owner: address,
    }

    struct NewResolverEvent has copy, drop {
        node: String,
        resolver: address,
    }

    struct NewTTLEvent has copy, drop {
        node: String,
        ttl: u64,
    }

    struct NewRecordEvent has copy, drop {
        node: String,
        owner: address,
        resolver: address,
        ttl: u64,
    }

    struct ApprovalForAllEvent has copy, drop {
        sender: address,
        operator: address,
        approved: bool,
    }

    // objects of this type are stored in the registry's map
    struct Record has store, drop {
        node: String,
        owner: address,
        resolver: address,
        ttl: u64,
    }

    struct Registry has key {
        id: UID,
        records: VecMap<String, Record>,
        operators: VecMap<address, VecSet<address>>,
    }

    fun init(ctx: &mut TxContext) {
        let registry = Registry {
            id: object::new(ctx),
            records: vec_map::empty(),
            operators: vec_map::empty(),
        };
        // insert .sui TLD nodes
        new_record(
            &mut registry,
            string::utf8(SUI_BASE_NODE),
            tx_context::sender(ctx),
            @0x0,
            MAX_TTL,
        );
        new_record(
            &mut registry,
            string::utf8(ADDR_REVERSE_BASE_NODE),
            tx_context::sender(ctx),
            @0x0,
            MAX_TTL,
        );
        transfer::share_object(registry);
        transfer::transfer(AdminCap {
            id: object::new(ctx)
        }, tx_context::sender(ctx));
    }

    public fun owner(registry: &Registry, node: vector<u8>): address {
        if (record_exists(registry, &string::utf8(node))) {
            return vec_map::get(&registry.records, &string::utf8(node)).owner
        };
        abort ERecordNotExists
    }

    public fun resolver(registry: &Registry, node: vector<u8>): address {
        if (record_exists(registry, &string::utf8(node))) {
            return vec_map::get(&registry.records, &string::utf8(node)).resolver
        };
        abort ERecordNotExists
    }

    public fun ttl(registry: &Registry, node: vector<u8>): u64 {
        if (record_exists(registry, &string::utf8(node))) {
            return vec_map::get(&registry.records, &string::utf8(node)).ttl
        };
        abort ERecordNotExists
    }

    public fun record_exists(registry: &Registry, node: &String): bool {
        vec_map::contains(&registry.records, node)
    }

    public fun is_approval_for_all(registry: &Registry, operator: address, owner: address): bool {
        if (vec_map::contains(&registry.operators, &owner)) {
            let operators =
                vec_map::get(&registry.operators, &owner);
            if (vec_set::contains(operators, &operator)) return true;
        };
        false
    }

    public entry fun set_record(
        registry: &mut Registry,
        node: vector<u8>,
        owner: address,
        resolver: address,
        ttl: u64,
        ctx: &mut TxContext,
    ) {
        authorised(registry, node, ctx);

        let node = string::utf8(node);
        set_owner_or_create_record(
            registry,
            node,
            owner,
            option::some(resolver),
            option::some(ttl),
        );
        event::emit(NewRecordEvent { node, owner, resolver, ttl });

        let record = vec_map::get_mut(&mut registry.records, &node);
        record.resolver = resolver;
        record.ttl = ttl;
    }

    public entry fun set_subnode_record(
        registry: &mut Registry,
        node: vector<u8>,
        label: vector<u8>,
        owner: address,
        resolver: address,
        ttl: u64,
        ctx: &mut TxContext,
    ) {
        authorised(registry, node, ctx);

        let subnode = make_subnode(label, string::utf8(node));
        set_subnode_record_internal(registry, subnode, owner, resolver, ttl);
        event::emit(NewRecordEvent { node: subnode, owner, resolver, ttl });
    }

    public(friend) fun set_subnode_record_internal(
        registry: &mut Registry,
        subnode: String,
        owner: address,
        resolver: address,
        ttl: u64,
    ) {
        set_node_record_internal(registry, subnode, owner, resolver, ttl);
    }

    public entry fun set_subnode_owner(
        registry: &mut Registry,
        node: vector<u8>,
        label: vector<u8>,
        owner: address,
        ctx: &mut TxContext,
    ) {
        authorised(registry, node, ctx);

        set_subnode_owner_internal(registry, node, label, owner)
    }

    public entry fun set_owner(registry: &mut Registry, node: vector<u8>, owner: address, ctx: &mut TxContext) {
        authorised(registry, node, ctx);

        let node = string::utf8(node);
        let record = vec_map::get_mut(&mut registry.records, &node);
        record.owner = owner;
        event::emit(NewOwnerEvent { node, owner });
    }

    public entry fun set_resolver(registry: &mut Registry, node: vector<u8>, resolver: address, ctx: &mut TxContext) {
        authorised(registry, node, ctx);

        let record = vec_map::get_mut(&mut registry.records, &string::utf8(node));
        record.resolver = resolver;
        event::emit(NewResolverEvent { node: record.node, resolver });
    }

    public entry fun set_approval_for_all(registry: &mut Registry, operator: address, approved: bool, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        if (approved) {
            if (!vec_map::contains(&registry.operators, &sender))
                vec_map::insert(&mut registry.operators, sender, vec_set::empty());
            let operators =
                vec_map::get_mut(&mut registry.operators, &sender);
            if (!vec_set::contains(operators, &operator)) {
                vec_set::insert(operators, operator);
                event::emit(ApprovalForAllEvent { sender, operator, approved });
            }
        } else {
            if (vec_map::contains(&registry.operators, &sender)) {
                let operators =
                    vec_map::get_mut(&mut registry.operators, &sender);
                if (vec_set::contains(operators, &operator)) {
                    vec_set::remove(operators, &operator);
                    event::emit(ApprovalForAllEvent { sender, operator, approved });
                }
            }
        }
    }

    public entry fun set_TTL(registry: &mut Registry, node: vector<u8>, ttl: u64, ctx: &mut TxContext) {
        authorised(registry, node, ctx);

        let record = vec_map::get_mut(&mut registry.records, &string::utf8(node));
        record.ttl = ttl;
        event::emit(NewTTLEvent { node: record.node, ttl });
    }

    public(friend) fun make_subnode(label: vector<u8>, node: String): String {
        let subnode = string::utf8(label);
        string::append_utf8(&mut subnode, b".");
        string::append(&mut subnode, node);
        subnode
    }

    // this func is meant to be call by registrar, no need to check for owner
    public(friend) fun set_node_record_internal(
        registry: &mut Registry,
        node: String,
        owner: address,
        resolver: address,
        ttl: u64,
    ) {
        set_owner_or_create_record(
            registry,
            node,
            owner,
            option::some(resolver),
            option::some(ttl),
        );

        let record = vec_map::get_mut(&mut registry.records, &node);
        record.resolver = resolver;
        record.ttl = ttl;
    }

    // this func is meant to be call by registrar, no need to check for owner
    public(friend) fun set_subnode_owner_internal(
        registry: &mut Registry,
        node: vector<u8>,
        label: vector<u8>,
        owner: address,
    ) {
        let subnode = make_subnode(label, string::utf8(node));
        set_owner_or_create_record(
            registry,
            subnode,
            owner,
            option::none<address>(),
            option::none<u64>(),
        );
        event::emit(NewSubnodeOwnerEvent {
            base_node: string::utf8(node),
            label: string::utf8(label),
            owner,
        });
    }

    fun authorised(registry: &Registry, node: vector<u8>, ctx: &TxContext) {
        let owner = owner(registry, node);
        let sender = tx_context::sender(ctx);
        if (sender == owner) return;
        if (vec_map::contains(&registry.operators, &owner)) {
            let operators = vec_map::get(&registry.operators, &owner);
            if (vec_set::contains(operators, &sender)) return
        };
        abort EUnauthorized
    }

    fun set_resolver_and_TTL(registry: &mut Registry, node: String, resolver: address, ttl: u64) {
        let record = vec_map::get_mut(&mut registry.records, &node);

        if (record.resolver != resolver) {
            record.resolver = resolver;
            event::emit(NewResolverEvent { node, resolver });
        };

        if (record.ttl != ttl) {
            record.ttl = ttl;
            event::emit(NewTTLEvent { node, ttl });
        };
    }

    fun set_owner_or_create_record(
        registry: &mut Registry,
        node: String,
        owner: address,
        resolver: Option<address>,
        ttl: Option<u64>,
    ) {
        if (vec_map::contains(&registry.records, &node)) {
            let record = vec_map::get_mut(&mut registry.records, &node);
            record.owner = owner;
            return
        };
        if (option::is_none(&resolver)) option::fill(&mut resolver, @0x0);
        if (option::is_none(&ttl)) option::fill(&mut ttl, 0);
        new_record(
            registry,
            node,
            owner,
            option::extract(&mut resolver),
            option::extract(&mut ttl),
        );
    }

    fun new_record(
        registry: &mut Registry,
        node: String,
        owner: address,
        resolver: address,
        ttl: u64,
    ) {
        let record = Record {
            node,
            owner,
            resolver,
            ttl,
        };
        vec_map::insert(&mut registry.records, record.node, record);
    }

    #[test_only]
    friend suins::base_registry_tests;

    #[test_only]
    public fun get_record_at_index(registry: &Registry, index: u64): (&String, &Record) {
        vec_map::get_entry_by_idx(&registry.records, index)
    }
    
    #[test_only]
    public fun get_records_len(registry: &Registry): u64 { vec_map::size(&registry.records) }

    #[test_only]
    public fun get_record_node(record: &Record): String { record.node }

    #[test_only]
    public fun get_record_owner(record: &Record): address { record.owner }

    #[test_only]
    public fun get_record_resolver(record: &Record): address { record.resolver }

    #[test_only]
    public fun get_record_ttl(record: &Record): u64 { record.ttl }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) { init(ctx) }
}
