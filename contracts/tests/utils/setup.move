#[test_only]
module suins::test_setup {
    use sui::tx_context::TxContext;
    use suins::registrar::App as RegistrarApp;
    use suins::controller::App as ControllerApp;
    use suins::suins;

    public fun setup(ctx: &mut TxContext) {
        let suins = suins::init_for_testing(ctx);
        suins::authorize_app_for_testing<RegistrarApp>(&mut suins);
        suins::authorize_app_for_testing<ControllerApp>(&mut suins);
        suins::share_for_testing(suins)
    }
}
