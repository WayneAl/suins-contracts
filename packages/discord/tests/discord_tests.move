// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module discord::discord_tests {

    use sui::test_scenario::{Self, Scenario, ctx};
    use discord::discord::{Self, Discord, DiscordCap};
    use discord::test_payloads::{Self as tp};

    const ADMIN_ADDRESS: address = @0xA001;

    public fun test_init(): Scenario {
        let scenario_val = test_scenario::begin(ADMIN_ADDRESS);
        let scenario = &mut scenario_val;
        {
            discord::init_for_testing(ctx(scenario));
        };
        {
            test_scenario::next_tx(scenario, ADMIN_ADDRESS);
            let discord = test_scenario::take_shared<Discord>(scenario);
            // get admin cap
            let cap = test_scenario::take_from_sender<DiscordCap>(scenario);

            // prepare discord roles
            discord::add_discord_role(&cap,&mut discord, tp::get_nth_role(0), tp::get_nth_role_percentage(0));
            discord::add_discord_role(&cap,&mut discord, tp::get_nth_role(1), tp::get_nth_role_percentage(1));
            discord::add_discord_role(&cap,&mut discord, tp::get_nth_role(2), tp::get_nth_role_percentage(2));
            discord::add_discord_role(&cap,&mut discord, tp::get_nth_role(3), tp::get_nth_role_percentage(3));
            discord::add_discord_role(&cap,&mut discord, tp::get_nth_role(4), tp::get_nth_role_percentage(4));

            discord::set_public_key(&cap, &mut discord, tp::get_public_key());

            test_scenario::return_to_sender(scenario, cap);
            test_scenario::return_shared(discord);
        };
        scenario_val
    }

    public fun prepare_data(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, tp::get_nth_user(0));
        let discord = test_scenario::take_shared<Discord>(scenario);

        discord::attach_roles(&mut discord, tp::get_nth_attach_roles_signature(0), tp::get_nth_discord_id(0), vector[tp::get_nth_role(0), tp::get_nth_role(1)]);
        discord::attach_roles(&mut discord, tp::get_nth_attach_roles_signature(2), tp::get_nth_discord_id(1), vector[tp::get_nth_role(2), tp::get_nth_role(3)]);

        discord::set_address(&mut discord, tp::get_nth_address_mapping_signature(0), tp::get_nth_discord_id(0), tp::get_nth_user(0));
        discord::set_address(&mut discord, tp::get_nth_address_mapping_signature(1), tp::get_nth_discord_id(1), tp::get_nth_user(1));
        test_scenario::return_shared(discord);
    }

    // test all the flows!
    #[test]
    fun test_e2e() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        // prepare data and data mappings!
        prepare_data(scenario);
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 50, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(1));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 100, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(1));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 40, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(1));
            let discord = test_scenario::take_shared<Discord>(scenario);
            let member = discord::get_member(&discord, &tp::get_nth_discord_id(1));
            assert!(discord::available_points(member) == 10, 0);
            assert!(discord::coupons_claimed(member) == 2, 0);
            test_scenario::return_shared(discord);
        };

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=discord::discord::ESignatureNotMatch)]
    fun attach_roles_to_wrong_discord_id_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::attach_roles(&mut discord, tp::get_nth_attach_roles_signature(0), tp::get_nth_discord_id(1), vector[tp::get_nth_role(0), tp::get_nth_role(1)]);
            test_scenario::return_shared(discord);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=discord::discord::ESignatureNotMatch)]
    fun attach_invalid_roles_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::attach_roles(&mut discord, tp::get_nth_attach_roles_signature(0), tp::get_nth_discord_id(0), vector[tp::get_nth_role(1), tp::get_nth_role(2)]);
            test_scenario::return_shared(discord);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=discord::discord::ERoleAlreadyAssigned)]
    fun try_to_attach_role_twice_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);

            discord::attach_roles(&mut discord, tp::get_nth_attach_roles_signature(0), tp::get_nth_discord_id(0), vector[tp::get_nth_role(0), tp::get_nth_role(1)]);
            discord::attach_roles(&mut discord, tp::get_nth_attach_roles_signature(1), tp::get_nth_discord_id(0), vector[tp::get_nth_role(1), tp::get_nth_role(3)]);
    
            test_scenario::return_shared(discord);
        };
        // let scenario = &mut scenario_val;
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=discord::discord::ERoleNotExists)]
    fun try_to_attach_non_existing_role_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);

            discord::attach_roles(&mut discord, tp::get_nth_attach_roles_signature(3), tp::get_nth_discord_id(1), vector[5]);
            test_scenario::return_shared(discord);
        };
        // let scenario = &mut scenario_val;
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=discord::discord::ESignatureNotMatch)]
    fun try_to_attach_address_to_invalid_discord_id_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);

            discord::set_address(&mut discord, tp::get_nth_address_mapping_signature(0), tp::get_nth_discord_id(0), tp::get_nth_user(1));
            test_scenario::return_shared(discord);
        };
        // let scenario = &mut scenario_val;
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=discord::discord::ENotEnoughPoints)]
    fun claim_more_points_than_available_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        prepare_data(scenario);
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 60, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        test_scenario::end(scenario_val);
    }
    #[test, expected_failure(abort_code=discord::discord::ENotEnoughPoints)]
    fun claim_more_points_in_two_steps_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        prepare_data(scenario);
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 45, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(0));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 6, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        test_scenario::end(scenario_val);
    }


    #[test, expected_failure(abort_code=discord::discord::EInvalidDiscount)]
    fun claim_with_invalid_percentage_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        prepare_data(scenario);
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(1));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 110, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code=discord::discord::EAddressNoMapping)]
    fun claim_with_non_existing_user_failure() {
        let scenario_val = test_init();
        let scenario = &mut scenario_val;
        prepare_data(scenario);
        {
            test_scenario::next_tx(scenario, tp::get_nth_user(2));
            let discord = test_scenario::take_shared<Discord>(scenario);
            discord::claim_coupon(&mut discord, 50, ctx(scenario));
            test_scenario::return_shared(discord);
        };
        test_scenario::end(scenario_val);
    }
}
