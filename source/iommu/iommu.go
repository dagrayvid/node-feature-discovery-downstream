/*
Copyright 2018 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package iommu

import (
	"fmt"
	"io/ioutil"

	"openshift/node-feature-discovery/source"
)

const Name = "iommu"

// Implement FeatureSource interface
// Source implements FeatureSource interface
type Source struct{}

func (s Source) Name() string { return Name }

// NewConfig method of the FeatureSource interface
func (s *Source) NewConfig() source.Config { return nil }

// GetConfig method of the FeatureSource interface
func (s *Source) GetConfig() source.Config { return nil }

// SetConfig method of the FeatureSource interface
func (s *Source) SetConfig(source.Config) {}

func (s Source) Discover() (source.Features, error) {
	features := source.Features{}

	// Check if any iommu devices are available
	devices, err := ioutil.ReadDir(source.SysfsDir.Path("class/iommu/"))
	if err != nil {
		return nil, fmt.Errorf("Failed to check for IOMMU support: %v", err)
	}

	if len(devices) > 0 {
		features["enabled"] = true
	}

	return features, nil
}
