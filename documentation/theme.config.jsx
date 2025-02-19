// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

import React from 'react';
import { useRouter } from 'next/router';
import Footer from './components/footer';

export default {
    logo: <><img className="w-4 mx-4 inline" src="/logo.svg"></img><span>Sui Name Service Docs</span></>,
    docsRepositoryBase: 'https://github.com/MystenLabs/suins-contracts/tree/main/documentation',
    project: {
      link: 'https://github.com/MystenLabs/suins-contracts'
    },
    useNextSeoProps() {
      const { asPath } = useRouter();
  
      return {
        titleTemplate: asPath !== '/' ? '%s | SuiNS Docs' : 'SuiNS Docs',
        description:
          'Sui Name Space Documentation. Integrate SuiNS in your projects for the Sui blockchain.',
        openGraph: {
          title: 'SuiNS Docs',
          description:
            'Sui Name Space Documentation. Integrate SuiNS in your projects for the Sui blockchain.',
          site_name: 'Sui Name Space Docs',
        },
        additionalMetaTags: [{ content: 'Sui Name Space Docs', name: 'apple-mobile-web-app-title' }],
      };
    },
    feedback: {
      content: ""
    },
    editLink: {
      component: null
    },
    footer: {
      component: Footer,
    }
    // ... other theme options
  }