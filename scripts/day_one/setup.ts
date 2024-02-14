import { createTransferPolicy, queryTransferPolicy } from '@mysten/kiosk';
import { JsonRpcProvider, TransactionBlock } from '@mysten/sui.js';

import { mainPackage, Network } from '../config/constants';
import { addressConfig, AirdropConfig, mainnetConfig } from '../config/day_one';

export const dayOneType = (config: AirdropConfig) => `${config.packageId}::day_one::DayOne`;

export const createDayOneDisplay = async (tx: TransactionBlock, network: Network) => {
	const config = network === 'mainnet' ? mainnetConfig : addressConfig;

	const displayObject = {
		keys: ['name', 'description', 'link', 'image_url'],
		values: [
			'SuiNS Day 1 NFT #{serial}',
			'The SuiNS Day 1 NFT represents community members who have been with SuiNS since day 1 of launch.',
			'https://suins.io/',
			'https://suins.io/day_one_active_{active}.webp',
		],
	};

	const mainPackageConfig = mainPackage[network];

	let display = tx.moveCall({
		target: '0x2::display::new_with_fields',
		arguments: [
			tx.object(config.publisher),
			tx.pure(displayObject.keys),
			tx.pure(displayObject.values),
		],
		typeArguments: [dayOneType(config)],
	});

	tx.moveCall({
		target: '0x2::display::update_version',
		arguments: [display],
		typeArguments: [dayOneType(config)],
	});

	tx.transferObjects([display], tx.pure(mainPackageConfig.adminAddress));
};

export const createDayOneTransferPolicy = async (
	tx: TransactionBlock,
	provider: JsonRpcProvider,
	network: Network,
) => {
	const config = network === 'mainnet' ? mainnetConfig : addressConfig;

	const mainPackageConfig = mainPackage[network];
	const existingPolicy = await queryTransferPolicy(provider, dayOneType(config));

	if (existingPolicy.length > 0) {
		console.warn(`Type ${dayOneType} already had a tranfer policy so the transaction was skipped.`);
		return false;
	}
	// create transfer policy
	let transferPolicyCap = createTransferPolicy(tx, dayOneType(config), config.publisher);

	// transfer cap to owner
	tx.transferObjects([transferPolicyCap], tx.pure(mainPackageConfig.adminAddress, 'address'));

	return true;
};
