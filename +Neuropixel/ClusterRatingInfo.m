classdef ClusterRatingInfo < handle
    
    properties(Constant)
        defaultRatingValueSet = ["unrated", "noise", "lowfr", "unstable", "good"]';
    end
    
    properties(Transient, SetAccess=protected) % don't save KS to disk
        ks
    end
    
    properties(SetAccess=protected) 
        cluster_ids(:, 1) uint32
        subgroupSet(:, 1) string
        
        ratingValueSet(:, 1) string; 
    end
    
    properties
        % list of ratings corresponding to cluster_ids  
        ratings(:, 1) categorical % nClusters 
        
        % is cluster i usable within subgroup j?
        usableWithin(:, :) logical % nClusters x nSubgroups 
        
        % is cluster i stable across subgroups j and j+1
        stableAcross(:, :) logical % nClusters x nSubgroups-1 indiciating whether cluster is stable across the two adjacent subgroups
        
        includeCutoffSpikes(:, 1) logical % nClusters
    end
    
    properties(Dependent)
        nClusters
        nSubgroups
        defaultRating
    end
    
    methods
        function r = ClusterRatingInfo(varargin)
            p = inputParser();
            % specify this
            p.addParameter('subgroupSet', "All", @isstring);
            
            % specify one of:
            p.addParameter('ks', [], @(x) true);
            p.addParameter('app', [], @(x) isempty(x) || isvector(x));
            
            % optional
            p.addParameter('ratingValueSet', r.defaultRatingValueSet, @isstring);
            
            p.parse(varargin{:})
            
            r.ratingValueSet = p.Results.ratingValueSet;

            r.ks = p.Results.ks;
            if isempty(r.ks)
                cluster_ids = p.Results.cluster_ids;
                assert(~isempty(cluster_ids));
            else
                r.ks.load('loadFeatures', false, 'loadBatchwise', false, 'loadCutoff', false);
                cluster_ids = r.ks.cluster_ids;
                assert(~isempty(cluster_ids));
            end
            subgroupSet = p.Results.subgroupSet;
            if isempty(subgroupSet)
                subgroupSet = "";
            end
            r.initializeBlank(cluster_ids, subgroupSet);
        end
        
        function initializeBlank(r, cluster_ids, subgroupSet)
            r.cluster_ids = cluster_ids;
            r.subgroupSet = string(subgroupSet);
            
            r.ratings = repmat(r.defaultRating, r.nClusters, 1);
            r.usableWithin = true(r.nClusters, r.nSubgroups);
            r.stableAcross = true(r.nClusters, r.nSubgroups-1);
            r.includeCutoffSpikes = true(r.nClusters, 1);
        end
        
        function rating = convertToRatingCategorical(r, value)
            rating = categorical(string(value), r.ratingValueSet, 'Ordinal', true);
        end
        
        function setKilosortDataset(r, ks)
            assert(isa(ks, 'Neuropixel.KilosortDataset'));
            ks.load('loadBatchwise', false, 'loadFeatures', false);
            r.ks = ks;
            assert(~isempty(ks.cluster_ids));
            if ~isequal(r.cluster_ids, ks.cluster_ids)
                warning('KilsortDataset cluster_ids do not match ClusterRatingInfo''s');
                
                % update my properties to avoid mismatch
                [maskKeep, indSet] = ismember(r.cluster_ids, ks.cluster_ids);
                
                ratings = r.ratings; %#ok<*PROPLC>
                usableWithin = r.usableWithin;
                stableAcross = r.stableAcross;
                includeCutoffSpikes = r.includeCutoffSpikes;
                r.initializeBlank(ks.cluster_ids, r.subgroupSet);
                
                r.ratings(indSet) = ratings(maskKeep);
                r.usableWithin(indSet, :) = usableWithin(maskKeep, :);
                r.stableAcross(indSet, :) = stableAcross(maskKeep, :);
                r.includeCutoffSpikes(indSet, :) = includeCutoffSpikes(maskKeep, :);
            end
        end
        
        function n = get.nClusters(r)
            n = numel(r.cluster_ids);
        end
        
        function n = get.nSubgroups(r)
            n = max(1, numel(r.subgroupSet));
        end
        
        function rating = get.defaultRating(r)
            rating = r.convertToRatingCategorical(r.defaultRatingValueSet(1));
        end
        
        function [clusterInds, cluster_ids] = lookup_clusterIds(r, cluster_ids)
            if islogical(cluster_ids)
                cluster_ids = r.cluster_ids(cluster_ids);
             end
            [tf, clusterInds] = ismember(cluster_ids, r.cluster_ids);
            assert(all(tf), 'Some cluster ids were not found in r.cluster_ids');
        end
        
        function [subgroupInds, subgroups] = lookup_subgroups(r, subgroups)
            if isnumeric(subgroups)
                subgroupInds = subgroups;
                subgroups = r.subgroupSet(subgroupInds);
            else
                [tf, subgroupInds] = ismember(string(subgroups), r.subgroupSet);
                assert(all(tf), 'Some subgroups were not found in r.subgroupSet');
                subgroups = r.subgroupSet(subgroupInds);
            end
        end
        
        function [ratings, usableWithin, stableAcross, includeCutoffSpikes] = lookupClusterRatings(r, cluster_ids)
            cluster_inds = r.lookup_clusterIds(cluster_ids);
            ratings = r.ratings(cluster_inds);
            
            if nargout > 1
                usableWithin = r.usableWithin(cluster_inds, :);
            end
            if nargout > 2
                stableAcross = r.stableAcross(cluster_inds, :);
            end
            if nargout > 3
                includeCutoffSpikes = r.includeCutoffSpikes(cluster_inds);
            end
        end
        
        function tf = lookupClusterSubgroupUsableWithin(r, cluster_ids, subgroups)
            cluster_inds = r.lookup_clusterIds(cluster_ids);
            subgroup_inds = r.lookup_subgroups(subgroups);
            assert(max(subgroup_inds) <= r.nSubgroups);
            
            tf = r.usableWithin(cluster_inds, subgroup_inds);
        end
        
        function tf = lookupClusterSubgroupStableAcross(r, cluster_ids, subgroups)
            cluster_inds = r.lookup_clusterIds(cluster_ids);
            subgroup_inds = r.lookup_subgroups(subgroups);
            assert(max(subgroup_inds) < r.nSubgroups);
            
            tf = r.stableAcross(cluster_inds, subgroup_inds);
        end
        
        function setClusterRatings(r, cluster_ids, ratings, usableWithin, stableAcross, includeCutoffSpikes)
            cluster_inds = r.lookup_clusterIds(cluster_ids);
            nClu = numel(cluster_inds);
            nSub = r.nSubgroups;
            
            if ~isempty(ratings)
                r.ratings(cluster_inds) = r.convertToRatingCategorical(ratings);
            end
            
            if nargin > 3 && ~isempty(usableWithin)
                if size(usableWithin, 1) == 1
                    usableWithin = repmat(usableWithin, nClu, 1);
                end
                if size(usableWithin, 2) == 1
                    usableWithin = repmat(usableWithin, 1, nSub);
                end
                r.usableWithin(cluster_inds, :) = usableWithin;
            end
            
            if nargin > 4 && ~isempty(stableAcross)
                if size(stableAcross, 1) == 1
                    stableAcross = repmat(stableAcross, nClu, 1);
                end
                if size(stableAcross, 2) == 1
                    stableAcross = repmat(stableAcross, 1, nSub-1);
                end
                r.stableAcross(cluster_inds, :) = stableAcross;
            end
            
            if nargin > 5 && ~isempty(includeCutoffSpikes)
                r.includeCutoffSpikes(cluster_inds) = includeCutoffSpikes;
            end
        end
        
        function setClusterSubgroupUsableWithin(r, cluster_ids, subgroups, usableWithin)
            cluster_inds = r.lookup_clusterIds(cluster_ids);
            subgroup_inds = r.lookup_subgroups(subgroups);
            
            assert(size(usableWithin, 2) == 1 || size(usableWithin, 2) == numel(subgroups));
            r.usableWithin(cluster_inds, subgroup_inds) = usableWithin;
        end
        
        function setClusterSubgroupStableAcross(r, cluster_ids, subgroups, stableAcross)
            cluster_inds = r.lookup_clusterIds(cluster_ids);
            subgroup_inds = r.lookup_subgroups(subgroups);
            assert(all(subgroup_inds < r.nSubgroups));
            
            assert(size(stableAcross, 2) == 1 || size(stableAcross, 2) == numel(subgroups));
            r.stableAcross(cluster_inds, subgroup_inds) = stableAcross;
        end
        
        function countsByRatingSubgroup = computeClusterCounts(r, ratingValueSet, countUsableOnlyMask)
            % countsByRatingSubgroup is numel(ratingValueSet) x nSubgroups count of clusters
            % that have that rating and are listed as usableWithin that subgroup
            
            if nargin < 2
                ratingValueSet = r.ratingValueSet;
            end
            ratingValueSet = r.convertToRatingCategorical(ratingValueSet);
            if nargin < 3
                ratingsMaskCountAlways = false(r.nClusters, 1);
            else
                ratingsMaskCountAlways = ~ismember(r.ratings, ratingValueSet(countUsableOnlyMask));
            end
            
            nRatingValues = numel(ratingValueSet);
            countsByRatingSubgroup = zeros(nRatingValues, r.nSubgroups);
            
            for iS = 1:r.nSubgroups
                % count a rating if cluster marked usable, or rated something where we count it usable or not
                ratingsCountable = r.usableWithin(:, iS) | ratingsMaskCountAlways;
                countsByRatingSubgroup(:, iS) = histcounts(r.ratings(ratingsCountable), ratingValueSet);
            end
        end
        
        function cluster_ids = listClusterIdsUsableWithinSubgroup(r, subgroup, ratingsAccepted)
            % cluster_ids = listClusterIdsUsableWithinSubgroup(r, subgroup, ratingsAccepted)
            % 
            % list all cluster_ids that are:
            % - rated as one of the ratings in ratingsAccepted
            % - usable within the subgroup listed
            %
            % see listClusterIdsUsableAcrossSubgroupsWithRating if aggregating across multiple subgroups
            
            subgroup_ind = sort(r.lookup_subgroups(subgroup), 'ascend');
            mask_rating_accepted = ismember(r.ratings, r.convertToRatingCategorical(ratingsAccepted));
            mask_usable_all = all(r.usableWithin(:, subgroup_ind), 2);
            
            mask = mask_rating_accepted & mask_usable_all;
            cluster_ids = r.cluster_ids(mask);
        end
        
        function cluster_ids = listClusterIdsUsableAcrossSubgroupsWithRating(r, subgroups, ratingsAccepted)
            % cluster_ids = listClusterIdsUsableAcrossSubgroupsWithRating(r, subgroups, ratingsAccepted)
            %
            % list all cluster_ids that are:
            % - rated as one of the ratings in ratingsAccepted
            % - usable within each subgroup listed,
            % - stable across all interspersed subgroups 
            subgroup_inds = sort(r.lookup_subgroups(subgroups), 'ascend');
            mask_rating_accepted = ismember(r.ratings, r.convertToRatingCategorical(ratingsAccepted));
            mask_usable_all = all(r.usableWithin(:, subgroup_inds), 2);
            
            if numel(subgroup_inds) > 1
                mask_stable_across = all(r.stableAcross(:, min(subgroup_inds):max(subgroup_inds)), 2);
            else
                mask_stable_across = true(r.nClusters, 1);
            end
            
            mask = mask_rating_accepted & mask_usable_all & mask_stable_across;
            cluster_ids = r.cluster_ids(mask);
        end
    end
end