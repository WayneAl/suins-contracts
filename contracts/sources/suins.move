module suins::suins {
    use std::string::String;

    use sui::tx_context::{Self, TxContext};
    use sui::object::{UID, ID};
    use sui::table::Table;
    use sui::table;
    use sui::transfer;
    use sui::object;
    use sui::linked_table::LinkedTable;
    use sui::balance::Balance;
    use sui::sui::SUI;
    use sui::linked_table;
    use sui::balance;
    use sui::coin::{Self, Coin};
    use sui::vec_map::{Self, VecMap};
    use sui::dynamic_field as df;

    // use suins::config::{Self, Config};
    use suins::coin_tracker;

    friend suins::registry;
    friend suins::registrar;
    friend suins::controller;
    friend suins::auction;

    const MAX_U64: u64 = 18446744073709551615;

    /// An admin capability. The admin has full control over the application.
    /// This object must be issued only once during module initialization.
    struct AdminCap has key, store { id: UID }

    /// The main application object. Stores the state of the application,
    /// used for adding / removing and reading name records.
    struct SuiNS has key {
        id: UID,
        /// The total balance of the SuiNS.
        balance: Balance<SUI>,
        /// Maps domain names to name records (instance of `NameRecord`).
        registry: Table<String, NameRecord>,
        /// Map from addresses to a configured default domain
        reverse_registry: Table<address, String>,
        /// Maps tlds to registrar objects, each registrar object is responsible for domains of a particular tld.
        /// Registrar object is a mapping of domain names to registration records (instance of `RegistrationRecord`).
        /// A registrar object can be created by calling `new_tld` and has a record with key `tld` to represent its tld.
        registrars: Table<String, Table<String, RegistrationRecord>>,
        /// The controller object is responsible for managing the auction house.
        controller: Controller,
    }

    struct NameRecord has store {
        owner: address,
        /// The target address that this domain points to
        target_address: address,
        /// Additional data which may be stored in a record
        data: VecMap<String, String>,
    }

    /// each registration records has a corresponding name records
    struct RegistrationRecord has store, drop {
        expired_at: u64,
        nft_id: ID,
    }

    struct Controller has store {
        commitments: LinkedTable<vector<u8>, u64>,
        /// set by `configure_auction`
        /// the last epoch when bidder can call `finalize_auction`
        auction_house_finalized_at: u64,
    }

    /// The one-time-witness used to claim Publisher object.
    struct SUINS has drop {}

    // === Keys ===

    /// Key under which a configuration is stored.
    struct ConfigKey has copy, store, drop {}

    fun init(otw: SUINS, ctx: &mut TxContext) {
        sui::package::claim_and_keep(otw, ctx);

        // Create the admin capability; only performed once.
        transfer::transfer(AdminCap {
            id: object::new(ctx),
        }, tx_context::sender(ctx));

        let suins = SuiNS {
            id: object::new(ctx),
            balance: balance::zero(),
            registry: table::new(ctx),
            reverse_registry: table::new(ctx),
            registrars: table::new(ctx),
            controller: Controller {
                commitments: linked_table::new(ctx),
                auction_house_finalized_at: max_epoch_allowed(),
            }
        };

        transfer::share_object(suins);
    }

    // === Config management ===

    /// Attach dynamic configuration object to the application.
    public fun add_config<T: store, drop>(_: &AdminCap, self: &mut SuiNS, config: T) {
        df::add(&mut self.id, ConfigKey {}, config);
    }

    /// Get the configuration object for editing. The admin should put it back
    /// after editing (no extra check performed). Can be used to swap
    /// configuration since the `T` has `drop`. Eg nothing is stopping the admin
    /// from removing the configuration object and adding a new one.
    ///
    /// Fully taking the config also allows for edits within a transaction.
    public fun remove_config<T: store, drop>(_: &AdminCap, self: &mut SuiNS): T {
        df::remove(&mut self.id, ConfigKey {})
    }

    // === Admin actions ===

    /// Withdraw from the SuiNS balance directly and access the Coins within the same
    /// transaction. This is useful for the admin to withdraw funds from the SuiNS
    /// and then send them somewhere specific or keep at the address.
    ///
    /// TODO: check logic around coin management in the application.
    public fun withdraw(_: &AdminCap, self: &mut SuiNS, ctx: &mut TxContext): Coin<SUI> {
        let amount = balance(self);
        coin::take(&mut self.balance, amount, ctx)
    }

    // === Records creation ===

    public fun new_registration_record(expired_at: u64, nft_id: ID): RegistrationRecord {
        RegistrationRecord { expired_at, nft_id }
    }

    public fun new_name_record(owner: address, target_address: address): NameRecord {
        NameRecord {
            owner,
            target_address,
            data: vec_map::empty()
        }
    }

    // === Fields access ===

    public fun registry(self: &SuiNS): &Table<String, NameRecord> {
        &self.registry
    }

    public fun registrars(
        self: &SuiNS
    ): &Table<String, Table<String, RegistrationRecord>> {
        &self.registrars
    }

    public fun registrar(
        self: &SuiNS, tld: String
    ): &Table<String, RegistrationRecord> {
        table::borrow(&self.registrars, tld)
    }

    public fun name_record_owner(name_record: &NameRecord): address {
        name_record.owner
    }

    public fun name_record_target_address(name_record: &NameRecord): address {
        name_record.target_address
    }

    public fun registration_record_expired_at(record: &RegistrationRecord): u64 {
        record.expired_at
    }

    public fun registration_record_nft_id(record: &RegistrationRecord): ID {
        record.nft_id
    }

    public fun controller_commitments(
        self: &SuiNS
    ): &LinkedTable<vector<u8>, u64> {
        &self.controller.commitments
    }

    public fun controller_auction_house_finalized_at(self: &SuiNS): u64 {
        self.controller.auction_house_finalized_at
    }

    public fun max_epoch_allowed(): u64 {
        MAX_U64 - 365
    }

    public fun max_u64(): u64 {
        MAX_U64
    }

    public fun balance(self: &SuiNS): u64 {
        balance::value(&self.balance)
    }

    // === Friend and Private Functions ===

    public(friend) fun name_record_data(name_record: &NameRecord): &VecMap<String, String> {
        &name_record.data
    }

    public(friend) fun registry_mut(self: &mut SuiNS): &mut Table<String, NameRecord> {
        &mut self.registry
    }

    public(friend) fun reverse_registry(self: &SuiNS): &Table<address, String> {
        &self.reverse_registry
    }

    public(friend) fun reverse_registry_mut(self: &mut SuiNS): &mut Table<address, String> {
        &mut self.reverse_registry
    }

    public(friend) fun registrars_mut(self: &mut SuiNS): &mut Table<String, Table<String, RegistrationRecord>> {
        &mut self.registrars
    }

    public(friend) fun registrar_mut(self: &mut SuiNS, tld: String): &mut Table<String, RegistrationRecord> {
        table::borrow_mut(&mut self.registrars, tld)
    }

    public(friend) fun name_record_owner_mut(name_record: &mut NameRecord): &mut address {
        &mut name_record.owner
    }

    public(friend) fun name_record_target_address_mut(name_record: &mut NameRecord): &mut address {
        &mut name_record.target_address
    }

    public(friend) fun name_record_data_mut(name_record: &mut NameRecord): &mut VecMap<String, String> {
        &mut name_record.data
    }

    public(friend) fun registration_record_expired_at_mut(record: &mut RegistrationRecord): &mut u64 {
        &mut record.expired_at
    }

    public(friend) fun controller_commitments_mut(self: &mut SuiNS): &mut LinkedTable<vector<u8>, u64> {
        &mut self.controller.commitments
    }

    /// Use carefully
    public(friend) fun balance_mut(self: &mut SuiNS): &mut Balance<SUI> {
        &mut self.balance
    }

    public(friend) fun controller_auction_house_finalized_at_mut(self: &mut SuiNS): &mut u64 {
        &mut self.controller.auction_house_finalized_at
    }

    public(friend) fun add_to_balance(self: &mut SuiNS, coin: Coin<SUI>) {
        coin_tracker::track(@suins, coin::value(&coin));
        coin::put(&mut self.balance, coin);
    }

    public(friend) fun send_from_balance(self: &mut SuiNS, amount: u64, receiver: address, ctx: &mut TxContext) {
        let coin = coin::take(&mut self.balance, amount, ctx);
        transfer::public_transfer(coin, receiver);
        coin_tracker::track(receiver, amount);
    }

    // === Testing ===

    #[test_only] friend suins::registry_tests;
    #[test_only] friend suins::registry_tests_2;

    #[test_only]
    /// Wrapper of module initializer for testing
    public fun test_init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::transfer(admin_cap, tx_context::sender(ctx));

        let registry = table::new(ctx);
        let reverse_registry = table::new(ctx);
        let registrars = table::new(ctx);
        let controller = Controller {
            commitments: linked_table::new(ctx),
            auction_house_finalized_at: max_epoch_allowed(),
        };

        let suins = SuiNS {
            id: object::new(ctx),
            balance: balance::zero(),
            registry,
            reverse_registry,
            registrars,
            controller,
        };

        transfer::share_object(suins);
    }
}
