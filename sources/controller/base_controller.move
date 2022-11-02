module suins::base_controller {

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::ecdsa::keccak256;
    use sui::event;
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::sui::SUI;
    use sui::vec_map::{Self, VecMap};
    use suins::base_registry::{Registry, AdminCap};
    use suins::base_registrar::{Self, BaseRegistrar};
    use std::string::{Self, String};
    use std::bcs;
    use std::vector;
    use suins::configuration::Configuration;

    // TODO: remove later when timestamp is introduced
    // const MIN_COMMITMENT_AGE: u64 = 0;
    const MAX_COMMITMENT_AGE: u64 = 3;
    const REGISTRATION_FEE_PER_YEAR: u64 = 8;

    // errors in the range of 301..400 indicate Sui Controller errors
    const EInvalidResolverAddress: u64 = 301;
    const ECommitmentNotExists: u64 = 302;
    const ECommitmentNotValid: u64 = 303;
    const ECommitmentTooOld: u64 = 304;
    const ENotEnoughFee: u64 = 305;
    const EInvalidDuration: u64 = 306;
    const ELabelUnAvailable: u64 = 308;
    const ENoProfits: u64 = 310;
    const EInvalidLabel: u64 = 311;

    struct NameRegisteredEvent has copy, drop {
        node: String,
        label: String,
        owner: address,
        cost: u64,
        expiry: u64,
        nft_id: ID,
        resolver: address,
    }

    struct DefaultResolverChangedEvent has copy, drop {
        resolver: address,
    }

    struct NameRenewedEvent has copy, drop {
        node: String,
        label: String,
        cost: u64,
        expiry: u64,
    }

    struct BaseController has key {
        id: UID,
        commitments: VecMap<vector<u8>, u64>,
        balance: Balance<SUI>,
        default_addr_resolver: address,
    }

    fun init(ctx: &mut TxContext) {
        transfer::share_object(BaseController {
            id: object::new(ctx),
            commitments: vec_map::empty(),
            balance: balance::zero(),
            // cannot get the ID of name_resolver in `init`, admin need to update this by calling `set_default_resolver`
            default_addr_resolver: @0x0,
        });
    }

    public fun available(registrar: &BaseRegistrar, label: String, ctx: &TxContext): bool {
        base_registrar::available(registrar, label, ctx)
    }

    public entry fun set_default_resolver(_: &AdminCap, controller: &mut BaseController, resolver: address) {
        controller.default_addr_resolver = resolver;
        event::emit(DefaultResolverChangedEvent { resolver })
    }

    public entry fun renew(
        controller: &mut BaseController,
        registrar: &mut BaseRegistrar,
        label: vector<u8>,
        duration: u64,
        payment: &mut Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let no_year = duration / 365;
        if ((duration % 365) > 0) no_year = no_year + 1;
        let renew_fee = REGISTRATION_FEE_PER_YEAR * no_year;
        assert!(coin::value(payment) >= renew_fee, ENotEnoughFee);

        base_registrar::renew(registrar, label, duration, ctx);

        let coin_balance = coin::balance_mut(payment);
        let paid = balance::split(coin_balance, renew_fee);
        balance::join(&mut controller.balance, paid);

        event::emit(NameRenewedEvent {
            node: base_registrar::get_base_node(registrar),
            label: string::utf8(label),
            cost: renew_fee,
            expiry: duration,
        })
    }

    public entry fun withdraw(_: &AdminCap, controller: &mut BaseController, ctx: &mut TxContext) {
        let amount = balance::value(&controller.balance);
        assert!(amount > 0, ENoProfits);

        let coin = coin::take(&mut controller.balance, amount, ctx);
        transfer::transfer(coin, tx_context::sender(ctx));
    }

    public entry fun make_commitment_and_commit(
        controller: &mut BaseController,
        commitment: vector<u8>,
        ctx: &mut TxContext,
    ) {
        vec_map::insert(&mut controller.commitments, commitment, tx_context::epoch(ctx));
    }

    public entry fun register(
        controller: &mut BaseController,
        registrar: &mut BaseRegistrar,
        registry: &mut Registry,
        config: &Configuration,
        label: vector<u8>,
        owner: address,
        duration: u64,
        secret: vector<u8>,
        payment: &mut Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        let resolver = controller.default_addr_resolver;
        // TODO: duration in year only
        register_with_config(
            controller,
            registrar,
            registry,
            config,
            label,
            owner,
            duration,
            secret,
            resolver,
            payment,
            ctx,
        );
    }

    // anyone can register a domain at any level
    public entry fun register_with_config(
        controller: &mut BaseController,
        registrar: &mut BaseRegistrar,
        registry: &mut Registry,
        config: &Configuration,
        label: vector<u8>,
        owner: address,
        duration: u64,
        secret: vector<u8>,
        resolver: address,
        payment: &mut Coin<SUI>,
        ctx: &mut TxContext,
    ) {
        check_valid(string::utf8(label));

        let no_year = duration / 365;
        if ((duration % 365) > 0) no_year = no_year + 1;
        let registration_fee = REGISTRATION_FEE_PER_YEAR * no_year;
        assert!(coin::value(payment) >= registration_fee, ENotEnoughFee);

        let commitment = make_commitment(registrar, label, owner, secret);
        consume_commitment(controller, registrar, label, commitment, ctx);

        let nft_id = base_registrar::register(registrar, registry, config, label, owner, duration, resolver, ctx);
        // TODO: configure resolver

        event::emit(NameRegisteredEvent {
            node: base_registrar::get_base_node(registrar),
            label: string::utf8(label),
            owner,
            cost: registration_fee,
            expiry: tx_context::epoch(ctx) + duration,
            nft_id,
            resolver,
        });
        let coin_balance = coin::balance_mut(payment);
        let paid = balance::split(coin_balance, registration_fee);
        balance::join(&mut controller.balance, paid);
    }

    fun consume_commitment(
        controller: &mut BaseController,
        registrar: &BaseRegistrar,
        label: vector<u8>,
        commitment: vector<u8>,
        ctx: &TxContext,
    ) {
        assert!(vec_map::contains(&controller.commitments, &commitment), ECommitmentNotExists);
        // TODO: remove later when timestamp is introduced
        // assert!(
        //     *vec_map::get(&controller.commitments, &commitment) + MIN_COMMITMENT_AGE <= tx_context::epoch(ctx),
        //     ECommitmentNotValid
        // );
        assert!(
            *vec_map::get(&controller.commitments, &commitment) + MAX_COMMITMENT_AGE > tx_context::epoch(ctx),
            ECommitmentTooOld
        );
        assert!(available(registrar, string::utf8(label), ctx), ELabelUnAvailable);
        vec_map::remove(&mut controller.commitments, &commitment);
    }

    // Valid label have between 3 to 63 characters and contain only: lowercase (a-z), numbers (0-9), hyphen (-).
    // A name may not start or end with a hyphen
    fun check_valid(label: String) {
        let label_bytes = string::bytes(&label);
        let len = string::length(&label);

        assert!(2 < len && len < 64, EInvalidLabel);

        let index = 0;
        while (index < len) {
            let byte = *vector::borrow(label_bytes, index);
            if (!(
                    (byte >= 0x61 && byte <= 0x7A)                           // a-z
                        || (byte >= 0x30 && byte <= 0x39)                    // 0-9
                        || (byte == 0x2D && index != 0 && index != len - 1)  // -
            )) abort EInvalidLabel;

            index = index + 1;
        };
    }

    fun make_commitment(registrar: &BaseRegistrar, label: vector<u8>, owner: address, secret: vector<u8>): vector<u8> {
        let node = label;
        vector::append(&mut node, b".");
        vector::append(&mut node, base_registrar::get_base_node_bytes(registrar));

        let owner_bytes = bcs::to_bytes(&owner);
        vector::append(&mut node, owner_bytes);
        vector::append(&mut node, secret);
        keccak256(&node)
    }

    #[test_only]
    public fun test_make_commitment(registrar: &BaseRegistrar, label: vector<u8>, owner: address, secret: vector<u8>): vector<u8> {
        make_commitment(registrar, label, owner, secret)
    }

    #[test_only]
    public fun balance(controller: &BaseController): u64 {
        balance::value(&controller.balance)
    }

    #[test_only]
    public fun commitment_len(controller: &BaseController): u64 {
        vec_map::size(&controller.commitments)
    }

    #[test_only]
    public fun get_default_resolver(controller: &BaseController): address {
        controller.default_addr_resolver
    }

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) { init(ctx) }
}
