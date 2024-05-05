module friend_tech_addr::friend_tech {
    use std::option;
    use std::signer;
    use std::string;
    use std::vector;
    use aptos_std::math128;
    use aptos_std::math64;
    use aptos_framework::event;
    use aptos_framework::fungible_asset;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;

    // #[event]
    // struct CreateFAEvent has store, drop {
    //     creator_addr: address,
    //     fa_obj_addr: address,
    //     max_supply: option::Option<u128>,
    //     name: string::String,
    //     symbol: string::String,
    //     decimals: u8,
    //     icon_uri: string::String,
    //     project_uri: string::String,
    // }
    //
    // #[event]
    // struct MintFAEvent has store, drop {
    //     fa_obj_addr: address,
    //     amount: u64,
    //     recipient_addr: address,
    // }
    //
    // struct FAController has key {
    //     mint_ref: fungible_asset::MintRef,
    //     burn_ref: fungible_asset::BurnRef,
    //     transfer_ref: fungible_asset::TransferRef
    // }

    struct Holding {
        issuer_obj: object::Object<Issuer>,
        holder: address,
        shares: u64,
    }

    struct User has key {
        holdings: vector<object::Object<Holding>>,
    }

    struct Issuer has key {
        addr: address,
        social_media_handle: string::String,
        total_issued_shares: u64,
        // all share holders' holdings
        holder_holdings: vector<object::Object<Holding>>,
    }

    struct IssuerRegistry has key {
        issuers: vector<object::Object<Issuer>>
    }

    // If you deploy the module under an object, sender is the object's signer
    // If you deploy the moduelr under your own account, sender is your account's signer
    fun init_module(sender: &signer) {
        move_to(sender, IssuerRegistry {
            issuers: vector::empty()
        });
    }

    // ================================= Entry Functions ================================= //

    public entry fun create_fa(
        sender: &signer,
        max_supply: option::Option<u128>,
        name: string::String,
        symbol: string::String,
        decimals: u8,
        icon_uri: string::String,
        project_uri: string::String
    ) acquires Registry {
        let fa_obj_constructor_ref = &object::create_sticky_object(@launchpad_addr);
        let fa_obj_signer = object::generate_signer(fa_obj_constructor_ref);
        let fa_obj_addr = signer::address_of(&fa_obj_signer);
        let converted_max_supply = if (option::is_some(&max_supply)) {
            option::some(option::extract(&mut max_supply) * math128::pow(10, (decimals as u128)))
        } else {
            option::none()
        };
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            fa_obj_constructor_ref,
            converted_max_supply,
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri
        );
        let mint_ref = fungible_asset::generate_mint_ref(fa_obj_constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(fa_obj_constructor_ref);
        let transfer_ref = fungible_asset::generate_transfer_ref(fa_obj_constructor_ref);
        move_to(&fa_obj_signer, FAController {
            mint_ref,
            burn_ref,
            transfer_ref,
        });

        let registry = borrow_global_mut<Registry>(@launchpad_addr);
        vector::push_back(&mut registry.fa_objects, object::address_to_object(fa_obj_addr));

        event::emit(CreateFAEvent {
            creator_addr: signer::address_of(sender),
            fa_obj_addr,
            max_supply: converted_max_supply,
            name,
            symbol,
            decimals,
            icon_uri,
            project_uri,
        });
    }

    public entry fun mint_fa(
        sender: &signer,
        fa: object::Object<fungible_asset::Metadata>,
        amount: u64
    ) acquires FAController {
        let sender_addr = signer::address_of(sender);
        let fa_obj_addr = object::object_address(&fa);
        let config = borrow_global<FAController>(fa_obj_addr);
        let decimals = fungible_asset::decimals(fa);
        primary_fungible_store::mint(&config.mint_ref, sender_addr, amount * math64::pow(10, (decimals as u64)));
        event::emit(MintFAEvent {
            fa_obj_addr,
            amount,
            recipient_addr: sender_addr,
        });
    }

    // ================================= View Functions ================================== //

    #[view]
    public fun get_registry(): vector<object::Object<fungible_asset::Metadata>> acquires Registry {
        let registry = borrow_global<Registry>(@launchpad_addr);
        registry.fa_objects
    }

    #[view]
    public fun get_metadata(
        fa: object::Object<fungible_asset::Metadata>
    ): (string::String, string::String, u8) {
        (
            fungible_asset::name(fa),
            fungible_asset::symbol(fa),
            fungible_asset::decimals(fa),
        )
    }

    #[view]
    public fun get_current_supply(fa: object::Object<fungible_asset::Metadata>): u128 {
        let maybe_supply = fungible_asset::supply(fa);
        if (option::is_some(&maybe_supply)) {
            option::extract(&mut maybe_supply)
        } else {
            0
        }
    }

    #[view]
    public fun get_max_supply(fa: object::Object<fungible_asset::Metadata>): u128 {
        let maybe_supply = fungible_asset::maximum(fa);
        if (option::is_some(&maybe_supply)) {
            option::extract(&mut maybe_supply)
        } else {
            0
        }
    }

    #[view]
    public fun get_balance(fa: object::Object<fungible_asset::Metadata>, user: address): u64 {
        primary_fungible_store::balance(user, fa)
    }

    // ================================= Tests ================================== //

    #[test(sender = @launchpad_addr)]
    fun test_happy_path(sender: &signer) acquires Registry, FAController {
        let sender_addr = signer::address_of(sender);

        init_module(sender);

        // create first FA

        create_fa(
            sender,
            option::some(100),
            string::utf8(b"FA1"),
            string::utf8(b"FA1"),
            2,
            string::utf8(b"icon_url"),
            string::utf8(b"project_url")
        );
        let registry = get_registry();
        let fa_1 = *vector::borrow(&registry, vector::length(&registry) - 1);
        assert!(get_current_supply(fa_1) == 0, 1);

        mint_fa(sender, fa_1, 2);
        assert!(get_current_supply(fa_1) == 200, 2);
        assert!(get_balance(fa_1, sender_addr) == 200, 3);

        // create second FA

        create_fa(
            sender,
            option::some(100),
            string::utf8(b"FA2"),
            string::utf8(b"FA2"),
            3,
            string::utf8(b"icon_url"),
            string::utf8(b"project_url")
        );
        let registry = get_registry();
        let fa_2 = *vector::borrow(&registry, vector::length(&registry) - 1);
        assert!(get_current_supply(fa_2) == 0, 4);

        mint_fa(sender, fa_2, 3);
        assert!(get_current_supply(fa_2) == 3000, 5);
        assert!(get_balance(fa_2, sender_addr) == 3000, 6);
    }
}