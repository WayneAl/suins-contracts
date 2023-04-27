#[test_only]
module suins::controller_tests_2 {

    use sui::coin;
    use sui::test_scenario;
    use sui::sui::SUI;
    use sui::url;
    use suins::auction_tests::ctx_new;
    use suins::registrar::{Self, RegistrationNFT};
    use suins::registry;
    use suins::suins::{Self, AdminCap};
    use suins::configuration::{Self, Configuration};
    use suins::suins::SuiNS;
    use suins::controller;
    use std::option;
    use std::string::utf8;
   use sui::clock::{Self, Clock};
    use suins::controller_tests::{test_init, set_auction_config, make_commitment};
    use suins::controller_tests;

    const SUINS_ADDRESS: address = @0xA001;
    const FIRST_USER_ADDRESS: address = @0xB001;
    const SECOND_USER_ADDRESS: address = @0xB002;
    const FIRST_LABEL: vector<u8> = b"eastagile-123";
    const FIRST_DOMAIN_NAME: vector<u8> = b"eastagile-123.sui";
    const SECOND_LABEL: vector<u8> = b"suinameservice";
    const THIRD_LABEL: vector<u8> = b"thirdsuinameservice";
    const FIRST_SECRET: vector<u8> = b"oKz=QdYd)]ryKB%";
    const SECOND_SECRET: vector<u8> = b"a9f8d4a8daeda2f35f02";
    const FIRST_INVALID_LABEL: vector<u8> = b"east.agile";
    const SECOND_INVALID_LABEL: vector<u8> = b"ea";
    const THIRD_INVALID_LABEL: vector<u8> = b"zkaoxpcbarubhtxkunajudxezneyczueajbggrynkwbepxjqjxrigrtgglhfjpax";
    const AUCTIONED_LABEL: vector<u8> = b"suins";
    const AUCTIONED_DOMAIN_NAME: vector<u8> = b"suins.sui";
    const FOURTH_INVALID_LABEL: vector<u8> = b"-eastagile";
    const FIFTH_INVALID_LABEL: vector<u8> = b"east/?agile";
    const REFERRAL_CODE: vector<u8> = b"X43kS8";
    const DISCOUNT_CODE: vector<u8> = b"DC12345";
    const BIDDING_PERIOD: u64 = 3;
    const REVEAL_PERIOD: u64 = 3;
    const START_AUCTION_START_AT: u64 = 50;
    const START_AUCTION_END_AT: u64 = 120;
    const EXTRA_PERIOD_START_AT: u64 = 127;
    const EXTRA_PERIOD_END_AT: u64 = 156;
    const START_AN_AUCTION_AT: u64 = 110;
    const EXTRA_PERIOD: u64 = 30;
    const SUI_REGISTRAR: vector<u8> = b"sui";
    const MOVE_REGISTRAR: vector<u8> = b"move";
    const BIDDING_FEE: u64 = 1000000000;
    const START_AN_AUCTION_FEE: u64 = 10_000_000_000;
    const MIN_COMMITMENT_AGE_IN_MS: u64 = 300_000;
    const PRICE_OF_THREE_CHARACTER_DOMAIN: u64 = 1200 * 1_000_000_000;
    const PRICE_OF_FOUR_CHARACTER_DOMAIN: u64 = 200 * 1_000_000_000;
    const PRICE_OF_FIVE_AND_ABOVE_CHARACTER_DOMAIN: u64 = 50 * 1_000_000_000;
    const GRACE_PERIOD: u64 = 90;
    const DEFAULT_TX_HASH: vector<u8> = x"3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532";

    #[test]
    fun test_set_price_to_register_five_character_domain() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);

            configuration::set_price_of_five_and_above_character_domain(&admin_cap, &mut config, 1_000_000_000);

            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        make_commitment(&mut scenario, option::some(b"xyztu"));
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let clock = test_scenario::take_shared<Clock>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = ctx_new(
                @0x0,
                DEFAULT_TX_HASH,
                EXTRA_PERIOD_END_AT + 1,
                0
            );
            let coin = coin::mint_for_testing<SUI>(PRICE_OF_FIVE_AND_ABOVE_CHARACTER_DOMAIN * 3, &mut ctx);
            clock::increment_for_testing(&mut clock, MIN_COMMITMENT_AGE_IN_MS);

            assert!(!registrar::record_exists(&suins, SUI_REGISTRAR, FIRST_LABEL), 0);
            assert!(suins::balance(&suins) == 0, 0);
            assert!(controller::commitment_len(&suins) == 1, 0);
            assert!(!registry::record_exists(&suins, utf8(FIRST_DOMAIN_NAME)), 0);
            assert!(!test_scenario::has_most_recent_for_sender<RegistrationNFT>(&mut scenario), 0);

            controller::register(
                &mut suins,
                &mut config,
                utf8(b"xyztu"),
                FIRST_USER_ADDRESS,
                2,
                FIRST_SECRET,
                &mut coin,
                &clock,
                &mut ctx,
            );
            assert!(coin::value(&coin) == PRICE_OF_FIVE_AND_ABOVE_CHARACTER_DOMAIN * 3 - 1_000_000_000 * 2, 0);
            assert!(controller::commitment_len(&suins) == 0, 0);

            coin::burn_for_testing(coin);
            test_scenario::return_shared(config);
            test_scenario::return_shared(clock);
            test_scenario::return_shared(suins);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let nft = test_scenario::take_from_sender<RegistrationNFT>(&mut scenario);
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let (name, url) = registrar::get_nft_fields(&nft);
            registrar::assert_registrar_exists(&suins, SUI_REGISTRAR);

            assert!(suins::balance(&suins) == 1_000_000_000 * 2, 0);
            assert!(name == utf8(b"xyztu.sui"), 0);
            assert!(
                url == url::new_unsafe_from_bytes(b"ipfs://QmaLFg4tQYansFpyRqmDfABdkUVy66dHtpnkH15v1LPzcY"),
                0
            );

            let expired_at = registrar::get_record_expired_at(&suins, SUI_REGISTRAR, b"xyztu");
            assert!(expired_at == EXTRA_PERIOD_END_AT + 1 + 730, 0);

            let (owner, target_address) = registry::get_name_record_all_fields(&suins, utf8(b"xyztu.sui"));
            assert!(owner == FIRST_USER_ADDRESS, 0);
            assert!(target_address == FIRST_USER_ADDRESS, 0);

            test_scenario::return_to_sender(&mut scenario, nft);
            test_scenario::return_shared(suins);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EInvalidNewPrice)]
    fun test_set_price_to_register_five_character_domain_aborts_if_new_price_too_low() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);

            configuration::set_price_of_five_and_above_character_domain(&admin_cap, &mut config, 1_000_000_000 - 1);

            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = configuration::EInvalidNewPrice)]
    fun test_set_price_to_register_five_character_domain_aborts_if_new_price_too_high() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        test_scenario::next_tx(&mut scenario, SUINS_ADDRESS);
        {
            let admin_cap = test_scenario::take_from_sender<AdminCap>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);

            configuration::set_price_of_five_and_above_character_domain(&admin_cap, &mut config, 1_000_000 * 1_000_000_000 + 1);

            test_scenario::return_to_sender(&mut scenario, admin_cap);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }

    #[test, expected_failure(abort_code = registrar::EInvalidNewExpiredAt)]
    fun test_renew_aborts_if_more_than_5_years_3() {
        let scenario = test_init();
        set_auction_config(&mut scenario);
        controller_tests::register(&mut scenario);
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(PRICE_OF_FIVE_AND_ABOVE_CHARACTER_DOMAIN * 7 + 1, ctx);

            controller::renew(
                &mut suins,
                &config,
                utf8(FIRST_LABEL),
                3,
                &mut coin,
                ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };
        test_scenario::next_tx(&mut scenario, FIRST_USER_ADDRESS);
        {
            let suins = test_scenario::take_shared<SuiNS>(&mut scenario);
            let config = test_scenario::take_shared<Configuration>(&mut scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(PRICE_OF_FIVE_AND_ABOVE_CHARACTER_DOMAIN * 7 + 1, ctx);

            controller::renew(
                &mut suins,
                &config,
                utf8(FIRST_LABEL),
                3,
                &mut coin,
                ctx,
            );

            coin::burn_for_testing(coin);
            test_scenario::return_shared(suins);
            test_scenario::return_shared(config);
        };
        test_scenario::end(scenario);
    }
}
