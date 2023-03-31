#[test_only]
module suins::controller_tests {

    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, Scenario};
    use sui::sui::SUI;
    use sui::url;
    use sui::clock;
    use sui::dynamic_field;
    use suins::auction::{make_seal_bid, finalize_all_auctions_by_admin, AuctionHouse};
    use suins::auction;
    use suins::auction_tests::{start_an_auction_util, place_bid_util, reveal_bid_util, ctx_new};
    use suins::registrar::{Self, RegistrationNFT};
    use suins::registry::{Self, AdminCap};
    use suins::configuration::{Self, Configuration};
    use suins::entity::{Self, SuiNS};
    use suins::controller;
    use suins::emoji;
    use std::option::{Self, Option, some};
    use std::string::utf8;
    use std::vector;
    use suins::auction_tests;

    const SUINS_ADDRESS: address = @0xA001;
    const FIRST_USER_ADDRESS: address = @0xB001;
    const SECOND_USER_ADDRESS: address = @0xB002;
    const FIRST_RESOLVER_ADDRESS: address = @0xC001;
    const FIRST_LABEL: vector<u8> = b"eastagile-123";
    const FIRST_NODE: vector<u8> = b"eastagile-123.sui";
    const SECOND_LABEL: vector<u8> = b"suinameservice";
    const THIRD_LABEL: vector<u8> = b"thirdsuinameservice";
    const FIRST_SECRET: vector<u8> = b"oKz=QdYd)]ryKB%";
    const SECOND_SECRET: vector<u8> = b"a9f8d4a8daeda2f35f02";
    const FIRST_INVALID_LABEL: vector<u8> = b"east.agile";
    const SECOND_INVALID_LABEL: vector<u8> = b"ea";
    const THIRD_INVALID_LABEL: vector<u8> = b"zkaoxpcbarubhtxkunajudxezneyczueajbggrynkwbepxjqjxrigrtgglhfjpax";
    const AUCTIONED_LABEL: vector<u8> = b"suins";
    const AUCTIONED_NODE: vector<u8> = b"suins.sui";
    const FOURTH_INVALID_LABEL: vector<u8> = b"-eastagile";
    const FIFTH_INVALID_LABEL: vector<u8> = b"east/?agile";
    const REFERRAL_CODE: vector<u8> = b"X43kS8";
    const DISCOUNT_CODE: vector<u8> = b"DC12345";
    const BIDDING_PERIOD: u64 = 3;
    const REVEAL_PERIOD: u64 = 3;
    const START_AUCTION_START_AT: u64 = 50;
    const START_AUCTION_END_AT: u64 = 120;
    const EXTRA_PERIOD_START_AT: u64 = 127;
    const START_AN_AUCTION_AT: u64 = 110;
    const EXTRA_PERIOD: u64 = 30;
    const SUI_REGISTRAR: vector<u8> = b"sui";
    const MOVE_REGISTRAR: vector<u8> = b"move";

    fun test_init(): Scenario {
        let scenario = test_scenario::begin(SUINS_ADDRESS);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            registry::test_init(ctx);
            configuration::test_init(ctx);
            entity::test_init(ctx);
            auction::test_init(ctx);
            clock::create_for_testing(ctx);
        };
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::new_tld(&admin_cap, &mut suins, SUI_REGISTRAR, test_scenario::ctx(&mut scenario));
            registrar::new_tld(&admin_cap, &mut suins, MOVE_REGISTRAR, test_scenario::ctx(&mut scenario));
            configuration::new_referral_code(&admin_cap, &mut config, REFERRAL_CODE, 10, SECOND_USER_ADDRESS);
            configuration::new_discount_code(&admin_cap, &mut config, DISCOUNT_CODE, 15, FIRST_USER_ADDRESS);
            configuration::set_public_key(
                &admin_cap,
                &mut config,
                x"0445e28df251d0ec0f66f284f7d5598db7e68b1a196396e4e13a3942d1364812ae5ed65ebb3d20cbf073ad50c6bbafa92505dc9b306e30476e57919a63ac824cab"
            );

            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        scenario
    }

    fun make_commitment(scenario: &mut Scenario, label: Option<vector<u8>>) {
        test_scenario::next_tx(scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(scenario);
            let no_of_commitments = controller::commitment_len(&suins);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                0
            );
            if (option::is_none(&label)) label = option::some(FIRST_LABEL);
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                option::extract(&mut label),
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            assert!(controller::commitment_len(&suins) - no_of_commitments == 1, 0);

            test_scenario::return_shared(suins);
        };
    }

    fun register(scenario: &mut Scenario) {
        make_commitment(scenario, option::none());

        // register
        test_scenario::next_tx(scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(scenario);
            let config = test_scenario::take_shared<Configuration>(scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(1000001, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(scenario), 0);

            controller::register_with_config(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == FIRST_RESOLVER_ADDRESS, 0);
            assert!(ttl == 0, 0);


            test_scenario::return_to_sender(scenario, nft);
            test_scenario::return_shared(suins);
        };
    }

    #[test]
    fun test_make_commitment() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::commitment_len(&suins) == 0, 0);
            test_scenario::return_shared(suins);
        };
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::commitment_len(&suins) == 1, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(controller::commitment_len(&suins) == 1, 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1000000, 0);
            assert!(controller::commitment_len(&suins) == 0, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 21 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ECommitmentNotExists)]
    fun test_register_abort_with_difference_label() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(1000001, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, SECOND_LABEL), 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                SECOND_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ECommitmentNotExists)]
    fun test_register_abort_with_wrong_secret() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(1000001, &mut ctx);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                SECOND_LABEL,
                FIRST_USER_ADDRESS,
                1,
                SECOND_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ECommitmentNotExists)]
    fun test_register_abort_with_wrong_owner() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(1000001, &mut ctx);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                SECOND_LABEL,
                SECOND_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ECommitmentTooOld)]
    fun test_register_abort_if_called_too_late() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user call `register` in the same epoch as `commit`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                53,
                0
            );
            let coin = coin::mint_for_testing<SUI>(1000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ENotEnoughFee)]
    fun test_register_abort_if_not_enough_fee() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                52,
                0
            );
            let coin = coin::mint_for_testing<SUI>(9999, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ELabelUnAvailable)]
    fun test_register_abort_if_label_was_registered_before() {
        let scenario = test_init();
        register(&mut scenario);
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(1000001, &mut ctx);
            assert!(controller::get_balance(&suins) == 1000000, 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_works_if_previous_registration_is_expired() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                599,
                10
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                SECOND_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                600,
                20
            );
            let coin = coin::mint_for_testing<SUI>(1000001, &mut ctx);
            assert!(controller::get_balance(&suins) == 1000000, 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                SECOND_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 600 + 365, 0);
            assert!(owner == SECOND_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == SECOND_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            let registrar = registrar::get_registrar(&suins, SUI_REGISTRAR);
            registrar::assert_nft_not_expires(
                registrar,
                utf8(SUI_REGISTRAR),
                &nft,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::ENFTExpired)]
    fun test_register_works_if_previous_registration_is_expired_2() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                599,
                10
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                SECOND_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                600,
                20
            );
            let coin = coin::mint_for_testing<SUI>(1000001, &mut ctx);
            assert!(controller::get_balance(&suins) == 1000000, 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                SECOND_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            let registrar = registrar::get_registrar(&suins, SUI_REGISTRAR);
            registrar::assert_nft_not_expires(
                registrar,
                utf8(SUI_REGISTRAR),
                &nft,
                test_scenario::ctx(&mut scenario)
            );

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_config() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(4000001, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);

            controller::register_with_config(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                &mut ctx,
            );
            assert!(coin::value(&coin) == 2000001, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);


            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == FIRST_RESOLVER_ADDRESS, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };

        // withdraw
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(!test_scenario::has_most_recent_for_sender<Coin<SUI>>(&mut scenario), 0);

            controller::withdraw(&admin_cap, &mut suins, test_scenario::ctx(&mut scenario));
            assert!(controller::get_balance(&suins) == 0, 0);

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            assert!(test_scenario::has_most_recent_for_sender<Coin<SUI>>(&mut scenario), 0);
            let coin = test_scenario::take_from_sender<Coin<SUI>>(&mut scenario);
            assert!(coin::value(&coin) == 2000000, 0);
            test_scenario::return_to_sender(&mut scenario, coin);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_with_config_abort_with_too_short_label() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(10001, test_scenario::ctx(&mut scenario));

            controller::register_with_config(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                SECOND_INVALID_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                test_scenario::ctx(&mut scenario),
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };

        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_with_config_abort_with_too_long_label() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(1000001, test_scenario::ctx(&mut scenario));

            controller::register_with_config(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                THIRD_INVALID_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                test_scenario::ctx(&mut scenario),
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_with_config_abort_if_label_starts_with_hyphen() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(10001, test_scenario::ctx(&mut scenario));

            controller::register_with_config(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FOURTH_INVALID_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                test_scenario::ctx(&mut scenario),
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_with_config_abort_with_invalid_label() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(1000001, test_scenario::ctx(&mut scenario));

            controller::register_with_config(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIFTH_INVALID_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                test_scenario::ctx(&mut scenario),
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ENoProfits)]
    fun test_withdraw_abort_if_no_profits() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            controller::withdraw(&admin_cap, &mut suins, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_abort_if_label_is_reserved_for_auction() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(10000001, test_scenario::ctx(&mut scenario));

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                test_scenario::ctx(&mut scenario),
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_abort_if_label_is_invalid() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                0
            );

            assert!(controller::commitment_len(&suins) == 0, 0);

            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_INVALID_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            assert!(controller::commitment_len(&suins) == 1, 0);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(10001, &mut ctx);

            controller::register_with_config(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_INVALID_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_renew() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(2000001, ctx);

            assert!(registrar::name_expires_at(&suins, SUI_REGISTRAR, FIRST_LABEL) == 416, 0);
            assert!(controller::get_balance(&suins) == 1000000, 0);

            controller::renew(
                &mut suins,
                SUI_REGISTRAR,
                FIRST_LABEL,
                2,
                &mut coin,
                ctx,
            );

            assert!(coin::value(&coin) == 1, 0);
            assert!(registrar::name_expires_at(&suins, SUI_REGISTRAR, FIRST_LABEL) == 1146, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::get_balance(&suins) == 3000000, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::ELabelNotExists)]
    fun test_renew_abort_if_label_not_exists() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(1000001, ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);

            controller::renew(
                &mut suins,
                SUI_REGISTRAR,
                FIRST_LABEL,
                1,
                &mut coin,
                ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::ELabelExpired)]
    fun test_renew_abort_if_label_expired() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                1051,
                0
            );
            let coin = coin::mint_for_testing<SUI>(10000001, &mut ctx);

            controller::renew(
                &mut suins,
                SUI_REGISTRAR,
                FIRST_LABEL,
                1,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ENotEnoughFee)]
    fun test_renew_abort_if_not_enough_fee() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(4, ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);

            controller::renew(
                &mut suins,
                SUI_REGISTRAR,
                FIRST_LABEL,
                1,
                &mut coin,
                ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_set_default_resolver() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::get_default_resolver(&suins) == @0x0, 0);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            controller::set_default_resolver(&admin_cap, &mut suins, FIRST_RESOLVER_ADDRESS);
            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::get_default_resolver(&suins) == FIRST_RESOLVER_ADDRESS, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_remove_outdated_commitment() {
        let scenario = test_init();
        // outdated commitment
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                10,
                0
            );

            assert!(controller::commitment_len(&suins) == 0, 0);

            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            assert!(controller::commitment_len(&suins) == 1, 0);
            test_scenario::return_shared(suins);
        };

        // outdated commitment
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                30,
                0
            );

            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                SECOND_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            assert!(controller::commitment_len(&suins) == 1, 0);

            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                48,
                0
            );

            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                SECOND_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            assert!(controller::commitment_len(&suins) == 1, 0);

            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                0
            );

            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                SECOND_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            assert!(controller::commitment_len(&suins) == 2, 0);

            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(2000001, &mut ctx);

            assert!(controller::commitment_len(&suins) == 2, 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                SECOND_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            assert!(coin::value(&coin) == 1, 0);
            assert!(controller::commitment_len(&suins) == 1, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_referral_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                b"",
                &mut ctx,
            );

            assert!(coin::value(&coin) == 1000000, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let coin = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            assert!(coin::value(&coin) == 200000, 0);
            assert!(controller::get_balance(&suins) == 1800000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_to_address(SECOND_USER_ADDRESS, coin);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_config_referral_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(4000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_config_and_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                3,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                REFERRAL_CODE,
                b"",
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1000000, 0);
            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let coin = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            assert!(coin::value(&coin) == 300000, 0);
            assert!(controller::get_balance(&suins) == 2700000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 1095, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == FIRST_RESOLVER_ADDRESS, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_to_address(SECOND_USER_ADDRESS, coin);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_apply_referral() {
        let scenario = test_init();
        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let config =
                test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin1 = coin::mint_for_testing<SUI>(4000000, ctx);
            let coin2 = coin::mint_for_testing<SUI>(909, ctx);

            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);
            controller::apply_referral_code_test(&config, &mut coin1, 4000000, REFERRAL_CODE, ctx);
            assert!(coin::value(&coin1) == 3600000, 0);

            controller::apply_referral_code_test(&config, &mut coin2, 909, REFERRAL_CODE, ctx);
            assert!(coin::value(&coin2) == 810, 0);

            coin::burn_for_testing(coin2);
            coin::burn_for_testing(coin1);
            test_scenario::return_shared(config);
        };

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let coin1 = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);
            let coin2 = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);

            assert!(coin::value(&coin1) == 99, 0);
            assert!(coin::value(&coin2) == 400000, 0);

            test_scenario::return_to_address(SECOND_USER_ADDRESS, coin1);
            test_scenario::return_to_address(SECOND_USER_ADDRESS, coin2);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_discount_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                b"",
                DISCOUNT_CODE,
                &mut ctx,
            );

            assert!(coin::value(&coin) == 1300000, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            assert!(controller::get_balance(&suins) == 1700000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EOwnerUnauthorized)]
    fun test_register_with_discount_code_abort_if_unauthorized() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let ctx = ctx_new(
                SECOND_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                b"",
                DISCOUNT_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EDiscountCodeNotExists)]
    fun test_register_with_discount_code_abort_with_invalid_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                b"",
                REFERRAL_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_config_and_discount_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_config_and_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                b"",
                DISCOUNT_CODE,
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1300000, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            assert!(controller::get_balance(&suins) == 1700000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == FIRST_RESOLVER_ADDRESS, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EOwnerUnauthorized)]
    fun test_register_with_config_and_discount_code_abort_if_unauthorized() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, SECOND_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                SECOND_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                b"",
                DISCOUNT_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EDiscountCodeNotExists)]
    fun test_register_with_config_and_discount_code_abort_with_invalid_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                b"",
                REFERRAL_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EDiscountCodeNotExists)]
    fun test_register_with_discount_code_abort_if_being_used_twice() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                b"",
                DISCOUNT_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                60,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                SECOND_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                61,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                SECOND_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                b"",
                DISCOUNT_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_referral_code_works_if_code_is_used_twice() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                b"",
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1000000, 0);
            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let coin = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(coin::value(&coin) == 200000, 0);
            assert!(controller::get_balance(&suins) == 1800000, 0);

            test_scenario::return_to_address(SECOND_USER_ADDRESS, coin);
            test_scenario::return_shared(suins);
        };
        make_commitment(&mut scenario, option::some(SECOND_LABEL));
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                2
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, SECOND_LABEL), 0);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                SECOND_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                b"",
                &mut ctx,
            );
            assert!(coin::value(&coin) == 2000000, 0);
            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let coin1 = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);
            let coin2 = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(coin::value(&coin1) == 100000, 0);
            assert!(coin::value(&coin2) == 200000, 0);
            assert!(controller::get_balance(&suins) == 2700000, 0);

            test_scenario::return_to_address(SECOND_USER_ADDRESS, coin2);
            test_scenario::return_shared(suins);
            test_scenario::return_to_address(SECOND_USER_ADDRESS, coin1);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EReferralCodeNotExists)]
    fun test_register_with_referral_code_abort_with_wrong_referral_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                DISCOUNT_CODE,
                b"",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_emoji() {
        let scenario = test_init();
        let node = vector[104, 109, 109, 109, 49, 240, 159, 145, 180];
        let domain_name = vector[104, 109, 109, 109, 49, 240, 159, 145, 180, 46, 115, 117, 105];
        make_commitment(&mut scenario, option::some(node));

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, node), 0);
            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(controller::commitment_len(&suins) == 1, 0);
            assert!(!registry::record_exists(&suins, utf8(domain_name)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                node,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1000000, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(name == utf8(domain_name), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, node);
            assert!(expiry == 51 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, domain_name);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_code_apply_both_types_of_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1300000, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let coin = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            assert!(coin::value(&coin) == 170000, 0);
            assert!(controller::get_balance(&suins) == 1700000 - 170000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EReferralCodeNotExists)]
    fun test_register_with_code_if_use_wrong_referral_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                DISCOUNT_CODE,
                DISCOUNT_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EDiscountCodeNotExists)]
    fun test_register_with_code_if_use_wrong_discount_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            controller::register_with_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                REFERRAL_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_config_and_code_apply_both_types_of_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_config_and_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1300000, 0);
            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let coin = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            assert!(coin::value(&coin) == 170000, 0);
            assert!(controller::get_balance(&suins) == 1700000 - 170000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == FIRST_RESOLVER_ADDRESS, 0);
            assert!(ttl == 0, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EReferralCodeNotExists)]
    fun test_register_with_config_and_code_if_use_wrong_referral_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            controller::register_with_config_and_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                DISCOUNT_CODE,
                DISCOUNT_CODE,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EDiscountCodeNotExists)]
    fun test_register_with_config_and_code_if_use_wrong_discount_code() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            controller::register_with_config_and_code(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                REFERRAL_CODE,
                REFERRAL_CODE,
                &mut ctx,
            );
            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    fun set_auction_config(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(scenario);
            let suins = test_scenario::take_shared<SuiNS>(scenario);
            auction::configure_auction(
                &admin_cap,
                &mut auction,
                &mut suins,
                START_AUCTION_START_AT,
                START_AUCTION_END_AT,
                test_scenario::ctx(scenario)
            );
            test_scenario::return_shared(suins);
            test_scenario::return_shared(auction);
            test_scenario::return_to_sender(scenario, admin_cap);
        };
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_abort_if_register_short_domain_while_auction_not_start_yet() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_work_if_register_long_domain_while_auction_not_start_yet() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 21 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_abort_if_register_short_domain_while_auction_is_happening() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                71,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_work_if_register_lonng_domain_while_auction_is_happening() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        make_commitment(&mut scenario, some(FIRST_LABEL));
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 51 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_work_for_long_domain_if_auction_is_over() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                220,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                221,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 221 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_work_for_short_domain_if_auction_is_over() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                220,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                221,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(AUCTIONED_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, AUCTIONED_LABEL);
            assert!(expiry == 221 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, AUCTIONED_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_work_if_name_not_wait_for_being_finalized() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                120,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                121,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 121 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_abort_if_name_are_waiting_for_being_finalized() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        start_an_auction_util(&mut scenario, AUCTIONED_LABEL);
        let seal_bid = make_seal_bid(AUCTIONED_LABEL, FIRST_USER_ADDRESS, 1000, b"CnRGhPvfCu");
        place_bid_util(&mut scenario, seal_bid, 1100, FIRST_USER_ADDRESS, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            reveal_bid_util(
                &mut auction,
                START_AN_AUCTION_AT + 1 + BIDDING_PERIOD,
                AUCTIONED_LABEL,
                1000,
                b"CnRGhPvfCu",
                FIRST_USER_ADDRESS,
                2
            );
            test_scenario::return_shared(auction);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + BIDDING_PERIOD + REVEAL_PERIOD,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + BIDDING_PERIOD + REVEAL_PERIOD + 1,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_abort_if_name_are_waiting_for_being_finalized_2() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + 1,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + 2,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_works_if_auctioned_label_not_have_a_winner_and_extra_time_passes() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        start_an_auction_util(&mut scenario, AUCTIONED_LABEL);

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            configuration::set_enable_controller(&admin_cap, &mut config, true);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + EXTRA_PERIOD + BIDDING_PERIOD + REVEAL_PERIOD,
                0
            );
            assert!(controller::get_balance(&suins) == 10000, 0);
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + EXTRA_PERIOD + BIDDING_PERIOD + REVEAL_PERIOD + 1,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(auction);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1010000, 0);
            assert!(name == utf8(AUCTIONED_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, AUCTIONED_LABEL);
            assert!(expiry == START_AUCTION_END_AT + EXTRA_PERIOD + BIDDING_PERIOD + REVEAL_PERIOD + 1 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, AUCTIONED_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_works_if_auctioned_label_not_have_a_winner_and_extra_time_not_yet_passes() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        start_an_auction_util(&mut scenario, AUCTIONED_LABEL);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + BIDDING_PERIOD + REVEAL_PERIOD,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + BIDDING_PERIOD + REVEAL_PERIOD + 1,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ERegistrationIsDisabled)]
    fun test_register_abort_if_registration_is_disabled() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            configuration::set_enable_controller(&admin_cap, &mut config, false);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                220,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                221,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(AUCTIONED_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 221 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, AUCTIONED_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ERegistrationIsDisabled)]
    fun test_register_abort_if_registration_is_disabled_2() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            configuration::set_enable_controller(&admin_cap, &mut config, false);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                220,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                221,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(AUCTIONED_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b""),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_NODE);
            assert!(expiry == 221 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, AUCTIONED_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_works_if_registration_is_reenabled() {
        let scenario = test_init();
        set_auction_config(&mut scenario);

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);

            configuration::set_enable_controller(&admin_cap, &mut config, false);

            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);

            configuration::set_enable_controller(&admin_cap, &mut config, true);

            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                220,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                221,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(AUCTIONED_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, AUCTIONED_LABEL);
            assert!(expiry == 221 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, AUCTIONED_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_commit_removes_only_50_outdated() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                47,
                0
            );
            let i: u8 = 0;

            while (i < 70) {
                let secret = FIRST_SECRET;
                vector::push_back(&mut secret, i);
                let commitment = controller::test_make_commitment(
                    SUI_REGISTRAR,
                    FIRST_LABEL,
                    FIRST_USER_ADDRESS,
                    secret
                );
                controller::commit(
                    &mut suins,
                    commitment,
                    &mut ctx,
                );

                i = i + 1;
            };

            assert!(controller::commitment_len(&suins) == 70, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                b"label-1",
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::commitment_len(&suins) == 21, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                b"label-2",
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::commitment_len(&suins) == 2, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                51,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                b"label-3",
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::commitment_len(&suins) == 3, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_commit_removes_only_50_outdated_2() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                47,
                0
            );
            let i: u8 = 0;

            while (i < 40) {
                let secret = FIRST_SECRET;
                vector::push_back(&mut secret, i);
                let commitment = controller::test_make_commitment(
                    SUI_REGISTRAR,
                    FIRST_LABEL,
                    FIRST_USER_ADDRESS,
                    secret
                );
                controller::commit(
                    &mut suins,
                    commitment,
                    &mut ctx,
                );

                i = i + 1;
            };
            assert!(controller::commitment_len(&suins) == 40, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                b"label-2",
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            assert!(controller::commitment_len(&suins) == 1, 0);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_image_aborts_with_empty_signature() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                x"",
                x"9e60301bec6f4b857eeaae141f3eb1373468500587d2798941b09e96ab390dc3",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,000000000000000000000000000000000000b001,375,abc",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_image_aborts_with_empty_hashed_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                x"1ade6c7ae5e0e2a1a4396b51c9c9df854504232e6dbf70ceb15b45ba5ab974a05045cc6fa92ed5f0a8ecd17c8e55947b867834222dc69d68b0749dd46d6902a4",
                x"",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,000000000000000000000000000000000000b001,375,abc",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_image_aborts_with_empty_raw_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                x"6aab9920d59442c5478c3f5b29db45518b40a3d76f1b396b70c902b557e93b206b0ce9ab84ce44277d84055da9dd10ff77c490ba8473cd86ead37be874b9662f",
                x"127552ffa7fb7c3718ee61851c49eba03ef7d0dc0933c7c5802cdd98226f6006",
                b"",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_image() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(controller::commitment_len(&suins) == 1, 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);

            controller::register_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                x"5509745079e180107d5b744dd460838bbe304fe4dcd1dc8e8e01c8377e3c30976efbc9d475844a1862fe88c01d2ba03a1bd3efeb4098788aad55a595111c7a3c",
                x"6c81f7ed6add6686c5048d4a6252deaa3e2b6bf38ee26f442cc801dce2338fae",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751,aa",
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1000000, 0);
            assert!(controller::commitment_len(&suins) == 0, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 21 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_config_and_image() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(4000001, &mut ctx);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);

            controller::register_with_config_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                x"3b3344937c2733eb37d60c24c4c5bb5b3fdc2305af9d9301c643b70d003852a5327b05a9a9bd66ad088282bc12a34b749648190f7863de6cd69ab3a19204d6ed",
                x"b6c60386fc06fa819113d904d866c4b2c8797a93785ae93b674fd24402686e4b",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751,;;;;",
                &mut ctx,
            );
            assert!(coin::value(&coin) == 2000001, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 21 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == FIRST_RESOLVER_ADDRESS, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };

        // withdraw
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(controller::get_balance(&suins) == 2000000, 0);
            assert!(!test_scenario::has_most_recent_for_sender<Coin<SUI>>(&mut scenario), 0);

            controller::withdraw(&admin_cap, &mut suins, test_scenario::ctx(&mut scenario));
            assert!(controller::get_balance(&suins) == 0, 0);

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            assert!(test_scenario::has_most_recent_for_sender<Coin<SUI>>(&mut scenario), 0);
            let coin = test_scenario::take_from_sender<Coin<SUI>>(&mut scenario);
            assert!(coin::value(&coin) == 2000000, 0);
            test_scenario::return_to_sender(&mut scenario, coin);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_config_and_image_aborts_with_empty_raw_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                x"b8d5c020ccf043fb1dde772067d54e254041ec4c8e137f5017158711e59e86933d1889cf4d9c6ad8ef57290cc00d99b7ba60da5c0db64a996f72af010acdd2b0",
                x"64d1c3d80ac32235d4bf1c5499ac362fd28b88eba2984e81cc36924be09f5a2d",
                b"",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_config_and_image_aborts_with_empty_signature() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                x"",
                x"64d1c3d80ac32235d4bf1c5499ac362fd28b88eba2984e81cc36924be09f5a2d",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_config_and_image_aborts_with_empty_hashed_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                x"b8d5c020ccf043fb1dde772067d54e254041ec4c8e137f5017158711e59e86933d1889cf4d9c6ad8ef57290cc00d99b7ba60da5c0db64a996f72af010acdd2b0",
                x"",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_code_and_image() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            // simulate user wait for next epoch to call `register`
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"47a547512876ed951e8a7ff05e0081517032882801592b1afdc822a98611583914ab16cb81f031c669a7650a8ff26c37429c7e85dd70c7068c8ab9f86dc4c667",
                x"87a36f92452b4b32bf624bed5e587d2595105a071b96c80b5f7c697dbf1cddef",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751,hmm",
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1300000, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let coin = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);

            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k"),
                0
            );
            assert!(coin::value(&coin) == 170000, 0);
            assert!(controller::get_balance(&suins) == 1700000 - 170000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 21 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_code_and_image_aborts_with_empty_signature() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"",
                x"64d1c3d80ac32235d4bf1c5499ac362fd28b88eba2984e81cc36924be09f5a2d",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_code_and_image_aborts_with_empty_hashed_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"b8d5c020ccf043fb1dde772067d54e254041ec4c8e137f5017158711e59e86933d1889cf4d9c6ad8ef57290cc00d99b7ba60da5c0db64a996f72af010acdd2b0",
                x"",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_code_and_image_aborts_with_empty_raw_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"b8d5c020ccf043fb1dde772067d54e254041ec4c8e137f5017158711e59e86933d1889cf4d9c6ad8ef57290cc00d99b7ba60da5c0db64a996f72af010acdd2b0",
                x"64d1c3d80ac32235d4bf1c5499ac362fd28b88eba2984e81cc36924be09f5a2d",
                b"",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_with_config_and_code_and_image() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            assert!(controller::get_balance(&suins) == 0, 0);
            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_NODE)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);
            assert!(!test_scenario::has_most_recent_for_address<Coin<SUI>>(SECOND_USER_ADDRESS), 0);

            controller::register_with_config_and_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"f3a51aacb6bf3cf41e778772a97c0f5dcd7fa812e38bb8b50f5f1ea9fc1b8983524048cd11163ed8f6dbcef0892397b87bdeca192d5ab3f2cedf8ad445e27ab0",
                x"dade7c2260ab75fb729a2d3b526e836c5408eb6a4e7bc59490b56a46c99e83f6",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751,817",
                &mut ctx,
            );
            assert!(coin::value(&coin) == 1300000, 0);
            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let coin = test_scenario::take_from_address<Coin<SUI>>(&mut scenario, SECOND_USER_ADDRESS);
            let (name, url) = registrar::get_nft_fields(&nft);

            assert!(name == utf8(FIRST_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k"),
                0
            );
            assert!(coin::value(&coin) == 170000, 0);
            assert!(controller::get_balance(&suins) == 1700000 - 170000, 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, FIRST_LABEL);
            assert!(expiry == 21 + 730, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, FIRST_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == FIRST_RESOLVER_ADDRESS, 0);
            assert!(ttl == 0, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_config_and_code_and_image_aborts_with_empty_signature() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"",
                x"64d1c3d80ac32235d4bf1c5499ac362fd28b88eba2984e81cc36924be09f5a2d",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_config_and_code_and_image_aborts_with_empty_hashed_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"b8d5c020ccf043fb1dde772067d54e254041ec4c8e137f5017158711e59e86933d1889cf4d9c6ad8ef57290cc00d99b7ba60da5c0db64a996f72af010acdd2b0",
                x"",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,751",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_register_with_config_and_code_and_image_aborts_with_empty_raw_message() {
        let scenario = test_init();
        make_commitment(&mut scenario, option::none());
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register_with_config_and_code_and_image(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                FIRST_LABEL,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                FIRST_RESOLVER_ADDRESS,
                &mut coin,
                REFERRAL_CODE,
                DISCOUNT_CODE,
                x"b8d5c020ccf043fb1dde772067d54e254041ec4c8e137f5017158711e59e86933d1889cf4d9c6ad8ef57290cc00d99b7ba60da5c0db64a996f72af010acdd2b0",
                x"64d1c3d80ac32235d4bf1c5499ac362fd28b88eba2984e81cc36924be09f5a2d",
                b"",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_renew_with_image() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(b"eastagile-123.sui"), 0);
            assert!(url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"), 0);

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(2000001, ctx);

            assert!(registrar::name_expires_at(&suins, SUI_REGISTRAR, FIRST_LABEL) == 416, 0);
            assert!(controller::get_balance(&suins) == 1000000, 0);

            controller::renew_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &config,
                FIRST_LABEL,
                2,
                &mut coin,
                &mut nft,
                x"146512d5ef5775a6d0135bdb27c4e2f1dc2fb58e55d9a98458fc4360fe21f683422b29e94fdb9ea71a6206cf91bd29f2d4dbb65fc8cccf5203e8ba638e7cd863",
                x"9432a8cd00cd6218e282ccc847b0432d4f0e7d33c8bb91d2e4283be0a2a7d0e1",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,1146,everywhere",
                ctx,
            );

            assert!(coin::value(&coin) == 1, 0);
            assert!(registrar::name_expires_at(&suins, SUI_REGISTRAR, FIRST_LABEL) == 1146, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(controller::get_balance(&suins) == 3000000, 0);
            assert!(name == utf8(b"eastagile-123.sui"), 0);
            assert!(url == url::new_unsafe_from_bytes(b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k"), 0);

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_renew_with_image_aborts_with_empty_signature() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(2000001, ctx);

            controller::renew_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &config,
                FIRST_LABEL,
                2,
                &mut coin,
                &mut nft,
                x"",
                x"8ae97b7af21e857a343b93f0ca8a132819aa4edd4bedcee3e3a37d8f9bb89821",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,1146",
                ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_renew_with_image_aborts_with_empty_hashed_msg() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(2000001, ctx);

            controller::renew_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &config,
                FIRST_LABEL,
                2,
                &mut coin,
                &mut nft,
                x"a8ae97b7af21e87a343b93f0ca8a132819aa4edd4bedcee3e3a37d8f9bb89821",
                x"",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,1146",
                ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidImageMessage)]
    fun test_renew_with_image_aborts_with_empty_raw_msg() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(2000001, ctx);

            controller::renew_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &config,
                FIRST_LABEL,
                2,
                &mut coin,
                &mut nft,
                x"a8ae97b7af21e85a343b93f0ca8a132819aa4edd4bedcee3e3a37d8f9bb89821",
                x"a8ae97b7af21857a343b93f0ca8a132819aa4edd4bedcee3e3a37d8f9bb89821",
                b"",
                ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::ELabelExpired)]
    fun test_renew_with_image_aborts_if_being_called_too_late() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                600,
                0
            );
            let coin = coin::mint_for_testing<SUI>(2000001, &mut ctx);

            assert!(registrar::name_expires_at(&suins, SUI_REGISTRAR, FIRST_LABEL) == 416, 0);

            controller::renew_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &config,
                FIRST_LABEL,
                2,
                &mut coin,
                &mut nft,
                x"9d1b824b2c7c3649cc967465393cc00cfa3e4c8e542ef0175a0525f91cb80b8721370eb6ca3f36896e0b740f99ebd02ea3e50480b19ac66466045b3e4763b14f",
                x"8ae97b7af21e857a343b93f0ca8a132819aa4edd4bedcee3e3a37d8f9bb89821",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,1146",
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_renew_with_image_works_if_being_called_in_grace_time() {
        let scenario = test_init();
        register(&mut scenario);

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(controller::get_balance(&suins) == 1000000, 0);
            assert!(name == utf8(b"eastagile-123.sui"), 0);
            assert!(url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"), 0);

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&scenario);
            let ctx = ctx_new(
                FIRST_USER_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                450,
                0
            );
            let coin = coin::mint_for_testing<SUI>(2000001, &mut ctx);

            assert!(registrar::name_expires_at(&suins, SUI_REGISTRAR, FIRST_LABEL) == 416, 0);
            assert!(controller::get_balance(&suins) == 1000000, 0);

            controller::renew_with_image(
                &mut suins,
                SUI_REGISTRAR,
                &config,
                FIRST_LABEL,
                2,
                &mut coin,
                &mut nft,
                x"bc83dff092e33a66644781a5987298d705bfb6dd5e7ca1f94b32f24036e896976c9770178df149cedb577ada1e660adb4a2894570c7c5c063c9e6ef84718660c",
                x"26b27673f1f87a943b887ffc6c5d2aa71a1ab6300c4a189f8b0212c94d6435b9",
                b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k,eastagile-123.sui,1146,abc",
                &mut ctx,
            );

            assert!(coin::value(&coin) == 1, 0);
            assert!(registrar::name_expires_at(&suins, SUI_REGISTRAR, FIRST_LABEL) == 1146, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);

            assert!(controller::get_balance(&suins) == 3000000, 0);
            assert!(name == utf8(b"eastagile-123.sui"), 0);
            assert!(url == url::new_unsafe_from_bytes(b"QmQdesiADN2mPnebRz3pvkGMKcb8Qhyb1ayW2ybvAueJ7k"), 0);

            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, nft);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_works_if_name_are_waiting_for_being_finalized_and_extra_time_not_passes() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        start_an_auction_util(&mut scenario, AUCTIONED_LABEL);
        let seal_bid = make_seal_bid(AUCTIONED_LABEL, FIRST_USER_ADDRESS, 1000, FIRST_SECRET);
        place_bid_util(&mut scenario, seal_bid, 1100, FIRST_USER_ADDRESS, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            reveal_bid_util(
                &mut auction,
                START_AN_AUCTION_AT + 1 + BIDDING_PERIOD,
                AUCTIONED_LABEL,
                1000,
                FIRST_SECRET,
                FIRST_USER_ADDRESS,
                2
            );
            test_scenario::return_shared(auction);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + EXTRA_PERIOD,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + EXTRA_PERIOD + 1,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_register_works_if_name_are_waiting_for_being_finalized_and_extra_time_passes() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        start_an_auction_util(&mut scenario, AUCTIONED_LABEL);
        let seal_bid = make_seal_bid(AUCTIONED_LABEL, FIRST_USER_ADDRESS, 1000, FIRST_SECRET);
        place_bid_util(&mut scenario, seal_bid, 1100, FIRST_USER_ADDRESS, option::none());

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            reveal_bid_util(
                &mut auction,
                START_AN_AUCTION_AT + 1 + BIDDING_PERIOD,
                AUCTIONED_LABEL,
                1000,
                FIRST_SECRET,
                FIRST_USER_ADDRESS,
                2
            );
            test_scenario::return_shared(auction);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + BIDDING_PERIOD + REVEAL_PERIOD + EXTRA_PERIOD,
                0
            );
            assert!(controller::get_balance(&suins) == 10000, 0);
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                START_AUCTION_END_AT + BIDDING_PERIOD + REVEAL_PERIOD + EXTRA_PERIOD + 1,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);

            assert!(controller::get_balance(&suins) == 1010000, 0);
            assert!(name == utf8(AUCTIONED_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, AUCTIONED_LABEL);
            assert!(
                expiry ==
                    START_AUCTION_END_AT + BIDDING_PERIOD + REVEAL_PERIOD + EXTRA_PERIOD + 1 + 365,
                0
            );
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, AUCTIONED_NODE);

            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_register_auctioned_label_aborts_if_in_extra_period_but_admin_calls_finalize_all_and_in_same_epoch() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        start_an_auction_util(&mut scenario, AUCTIONED_LABEL);

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let auction = test_scenario::take_shared<AuctionHouse>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            assert!(controller::get_balance(&suins) == 10000, 0);

            finalize_all_auctions_by_admin(
                &admin_cap,
                &mut auction,
                &mut suins,
                &config,
                FIRST_RESOLVER_ADDRESS,
                &mut auction_tests::ctx_util(SUINS_ADDRESS, EXTRA_PERIOD_START_AT, 20),
            );

            assert!(controller::get_balance(&suins) == 10000, 0);
            test_scenario::return_shared(auction);
            test_scenario::return_shared(suins);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };

        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                EXTRA_PERIOD_START_AT - 1,
                0
            );
            let commitment = controller::test_make_commitment(
                SUI_REGISTRAR,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );
            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                EXTRA_PERIOD_START_AT,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                AUCTIONED_LABEL,
                FIRST_USER_ADDRESS,
                1,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(controller::get_balance(&suins) == 1010000, 0);
            assert!(name == utf8(AUCTIONED_NODE), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, AUCTIONED_LABEL);
            assert!(expiry == EXTRA_PERIOD_START_AT + 1 + 365, 0);
            assert!(owner == FIRST_USER_ADDRESS, 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, AUCTIONED_NODE);
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test]
    fun test_new_reserved_domains() {
        let scenario = test_init();
        let first_node = b"abcde";
        let first_domain_name_sui = b"abcde.sui";
        let first_domain_name_move = b"abcde.move";
        let second_node = b"abcdefghijk";
        let second_domain_name_sui = b"abcdefghijk.sui";
        let second_domain_name_move = b"abcdefghijk.move";

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            assert!(registrar::is_available(&suins, utf8(SUI_REGISTRAR), utf8(first_node), ctx), 0);
            assert!(registrar::is_available(&suins, utf8(MOVE_REGISTRAR), utf8(first_node), ctx), 0);
            assert!(registrar::is_available(&suins, utf8(SUI_REGISTRAR), utf8(second_node), ctx), 0);
            assert!(registrar::is_available(&suins, utf8(MOVE_REGISTRAR),utf8(second_node), ctx), 0);

            assert!(!registry::record_exists(&suins, utf8(first_domain_name_sui)), 0);
            assert!(!registry::record_exists(&suins, utf8(first_domain_name_move)), 0);
            assert!(!registry::record_exists(&suins, utf8(second_domain_name_sui)), 0);
            assert!(!registry::record_exists(&suins, utf8(second_domain_name_move)), 0);

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcde.sui;abcde.move;abcdefghijk.sui;", @0x0, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                10
            );

            assert!(!registrar::is_available(&suins, utf8(SUI_REGISTRAR),utf8(first_node), ctx), 0);
            assert!(!registrar::is_available(&suins, utf8(MOVE_REGISTRAR),utf8(first_node), ctx), 0);
            assert!(!registrar::is_available(&suins, utf8(SUI_REGISTRAR),utf8(second_node), ctx), 0);
            assert!(registrar::is_available(&suins, utf8(MOVE_REGISTRAR),utf8(second_node), ctx), 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, first_node);
            assert!(expiry == 415, 0);
            assert!(owner == SUINS_ADDRESS, 0);
            let (expiry, owner) = registrar::get_record_detail(&suins, MOVE_REGISTRAR, first_node);
            assert!(expiry == 415, 0);
            assert!(owner == SUINS_ADDRESS, 0);
            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, second_node);
            assert!(expiry == 415, 0);
            assert!(owner == SUINS_ADDRESS, 0);

            assert!(registry::record_exists(&suins, utf8(first_domain_name_sui)), 0);
            assert!(registry::record_exists(&suins, utf8(first_domain_name_move)), 0);
            assert!(registry::record_exists(&suins, utf8(second_domain_name_sui)), 0);
            assert!(!registry::record_exists(&suins, utf8(second_domain_name_move)), 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, first_domain_name_sui);
            assert!(owner == SUINS_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);
            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, first_domain_name_move);
            assert!(owner == SUINS_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);
            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, second_domain_name_sui);
            assert!(owner == SUINS_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            let first_nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&first_nft);
            assert!(name == utf8(second_domain_name_sui), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            let second_nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&second_nft);
            assert!(name == utf8(first_domain_name_move), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            let third_nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&third_nft);
            assert!(name == utf8(first_domain_name_sui), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            test_scenario::return_to_sender(&mut scenario, third_nft);
            test_scenario::return_to_sender(&mut scenario, second_nft);
            test_scenario::return_to_sender(&mut scenario, first_nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                52,
                20
            );

            assert!(registrar::is_available(&suins, utf8(MOVE_REGISTRAR),utf8(second_node), ctx), 0);
            assert!(!registry::record_exists(&suins, utf8(second_domain_name_move)), 0);

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcdefghijk.move", @0x0B, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                30
            );

            assert!(!registrar::is_available(&suins, utf8(SUI_REGISTRAR),utf8(first_node), ctx), 0);
            assert!(!registrar::is_available(&suins, utf8(MOVE_REGISTRAR),utf8(first_node), ctx), 0);
            assert!(!registrar::is_available(&suins, utf8(SUI_REGISTRAR),utf8(second_node), ctx), 0);
            assert!(!registrar::is_available(&suins, utf8(MOVE_REGISTRAR),utf8(second_node), ctx), 0);

            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, first_node);
            assert!(expiry == 415, 0);
            assert!(owner == SUINS_ADDRESS, 0);
            let (expiry, owner) = registrar::get_record_detail(&suins, MOVE_REGISTRAR, first_node);
            assert!(expiry == 415, 0);
            assert!(owner == SUINS_ADDRESS, 0);
            let (expiry, owner) = registrar::get_record_detail(&suins, SUI_REGISTRAR, second_node);
            assert!(expiry == 415, 0);
            assert!(owner == SUINS_ADDRESS, 0);
            let (expiry, owner) = registrar::get_record_detail(&suins, MOVE_REGISTRAR, second_node);
            assert!(expiry == 417, 0);
            assert!(owner == @0x0B, 0);

            assert!(registry::record_exists(&suins, utf8(first_domain_name_sui)), 0);
            assert!(registry::record_exists(&suins, utf8(first_domain_name_move)), 0);
            assert!(registry::record_exists(&suins, utf8(second_domain_name_sui)), 0);
            assert!(registry::record_exists(&suins, utf8(second_domain_name_move)), 0);

            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, first_domain_name_sui);
            assert!(owner == SUINS_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);
            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, first_domain_name_move);
            assert!(owner == SUINS_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);
            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, second_domain_name_sui);
            assert!(owner == SUINS_ADDRESS, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);
            let (owner, resolver, ttl) = registry::get_record_by_domain_name(&suins, second_domain_name_move);
            assert!(owner == @0x0B, 0);
            assert!(resolver == @0x0, 0);
            assert!(ttl == 0, 0);

            let first_nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&first_nft);
            assert!(name == utf8(second_domain_name_sui), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            let second_nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&second_nft);
            assert!(name == utf8(first_domain_name_move), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            let third_nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&third_nft);
            assert!(name == utf8(first_domain_name_sui), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            test_scenario::return_to_sender(&mut scenario, first_nft);
            test_scenario::return_to_sender(&mut scenario, second_nft);
            test_scenario::return_to_sender(&mut scenario, third_nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, @0x0B);
        {
            let first_nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&first_nft);
            assert!(name == utf8(second_domain_name_move), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );
            test_scenario::return_to_sender(&mut scenario, first_nft);
        };
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                52,
                20
            );
            let emoji_node = vector[104, 109, 109, 109, 49, 240, 159, 145, 180];
            let emoji_domain_name = vector[104, 109, 109, 109, 49, 240, 159, 145, 180, 46, 115, 117, 105];

            assert!(registrar::is_available(&suins, utf8(SUI_REGISTRAR),utf8(emoji_node), ctx), 0);
            assert!(!registry::record_exists(&suins, utf8(emoji_domain_name)), 0);

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, emoji_domain_name, @0x0C, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::ELabelUnAvailable)]
    fun test_new_reserved_domains_aborts_with_dupdated_domain_names() {
        let scenario = test_init();
        let first_node = b"abcde";
        let first_domain_name_sui = b"abcde.sui";

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            assert!(registrar::is_available(&suins, utf8(SUI_REGISTRAR), utf8(first_node), ctx), 0);
            assert!(!registry::record_exists(&suins, utf8(first_domain_name_sui)), 0);

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcde.sui;abcde.sui;", @0x0, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = dynamic_field::EFieldDoesNotExist)]
    fun test_new_reserved_domains_aborts_with_malformed_domains() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcde..sui;", @0x0, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = dynamic_field::EFieldDoesNotExist)]
    fun test_new_reserved_domains_aborts_with_non_existence_tld() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcde.suins;", @0x0, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_new_reserved_domains_aborts_with_leading_dash_character() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"-abcde.sui;", @0x0, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidLabel)]
    fun test_new_reserved_domains_aborts_with_trailing_dash_character() {
        let scenario = test_init();

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcde-.move;", @0x0, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = emoji::EInvalidEmojiSequence)]
    fun test_new_reserved_domains_aborts_with_invalid_emoji() {
        let scenario = test_init();
        let invalid_emoji_domain_name = vector[241, 159, 152, 135, 119, 109, 109, 49, 240, 159, 145, 180, 46, 115, 117, 105];

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, invalid_emoji_domain_name, @0x0, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ELabelUnAvailable)]
    fun test_register_aborts_if_sui_name_is_reserved() {
        let scenario = test_init();
        let first_node = b"abcde";

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcde.sui;", SUINS_ADDRESS, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        make_commitment(&mut scenario, option::some(first_node));
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                SUI_REGISTRAR,
                &mut config,
                first_node,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );
            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = controller::ELabelUnAvailable)]
    fun test_register_aborts_if_move_name_is_reserved() {
        let scenario = test_init();
        let first_node = b"abcdefghijk";

        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = &mut ctx_new(
                SUINS_ADDRESS,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                2
            );

            controller::new_reserved_domains(&admin_cap, &mut suins, &config, b"abcdefghijk.move;", SUINS_ADDRESS, ctx);

            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
            test_scenario::return_to_sender(&mut scenario, admin_cap);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let no_of_commitments = controller::commitment_len(&suins);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                50,
                0
            );
            let commitment = controller::test_make_commitment(
                MOVE_REGISTRAR,
                first_node,
                FIRST_USER_ADDRESS,
                FIRST_SECRET
            );

            controller::commit(
                &mut suins,
                commitment,
                &mut ctx,
            );
            assert!(controller::commitment_len(&suins) - no_of_commitments == 1, 0);

            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532",
                21,
                0
            );
            let coin = coin::mint_for_testing<SUI>(3000000, &mut ctx);

            controller::register(
                &mut suins,
                MOVE_REGISTRAR,
                &mut config,
                first_node,
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &mut ctx,
            );
            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }
}
